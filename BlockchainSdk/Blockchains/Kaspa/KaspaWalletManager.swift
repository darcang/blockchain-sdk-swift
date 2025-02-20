//
//  KaspaWalletManager.swift
//  BlockchainSdk
//
//  Created by Andrey Chukavin on 10.03.2023.
//  Copyright © 2023 Tangem AG. All rights reserved.
//

import Foundation
import Combine

class KaspaWalletManager: BaseManager, WalletManager {
    var txBuilder: KaspaTransactionBuilder!
    var networkService: KaspaNetworkService!
    
    var currentHost: String { networkService.host }
    var allowsFeeSelection: Bool { false }
    
    override func update(completion: @escaping (Result<Void, Error>) -> Void) {
        let unconfirmedTransactionHashes = wallet.pendingTransactions.map { $0.hash }

        cancellable = networkService.getInfo(address: wallet.address, unconfirmedTransactionHashes: unconfirmedTransactionHashes)
            .sink { result in
                switch result {
                case .failure(let error):
                    self.wallet.clearAmounts()
                    completion(.failure(error))
                case .finished:
                    completion(.success(()))
                }
            } receiveValue: { [weak self] response in
                self?.updateWallet(response)
            }
    }
    
    func send(_ transaction: Transaction, signer: TransactionSigner) -> AnyPublisher<TransactionSendResult, SendTxError> {
        let kaspaTransaction: KaspaTransaction
        let hashes: [Data]
        
        do {
            let result = try txBuilder.buildForSign(transaction)
            kaspaTransaction = result.0
            hashes = result.1
        } catch {
            return .sendTxFail(error: error)
        }
        
        return signer.sign(hashes: hashes, walletPublicKey: wallet.publicKey)
            .tryMap { [weak self] signatures in
                guard let self = self else { throw WalletError.empty }
                
                return self.txBuilder.buildForSend(transaction: kaspaTransaction, signatures: signatures)
            }
            .flatMap { [weak self] tx -> AnyPublisher<KaspaTransactionResponse, Error> in
                guard let self = self else { return .emptyFail }
                
                let encodedRawTransactionData = try? JSONEncoder().encode(tx)
                
                return self.networkService
                    .send(transaction: KaspaTransactionRequest(transaction: tx))
                    .mapSendError(tx: encodedRawTransactionData?.hexString.lowercased())
                    .eraseToAnyPublisher()
            }
            .handleEvents(receiveOutput: { [weak self] in
                let mapper = PendingTransactionRecordMapper()
                let record = mapper.mapToPendingTransactionRecord(transaction: transaction, hash: $0.transactionId)
                self?.wallet.addPendingTransaction(record)
            })
            .map {
                TransactionSendResult(hash: $0.transactionId)
            }
            .eraseSendError()
            .eraseToAnyPublisher()
    }
    
    func getFee(amount: Amount, destination: String) -> AnyPublisher<[Fee], Error> {
        let numberOfUtxos = txBuilder.unspentOutputsCount(for: amount)
        guard numberOfUtxos > 0 else {
            return Fail(error: WalletError.failedToGetFee)
                .eraseToAnyPublisher()
        }
        
        let feePerUtxo = 10_000
        let fee = feePerUtxo * numberOfUtxos
        
        return Just([Fee(Amount(with: wallet.blockchain, value: Decimal(fee) / wallet.blockchain.decimalValue))])
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    private func updateWallet(_ info: KaspaAddressInfo) {
        self.wallet.add(amount: Amount(with: self.wallet.blockchain, value: info.balance))
        txBuilder.setUnspentOutputs(info.unspentOutputs)
        wallet.removePendingTransaction { hash in
            info.confirmedTransactionHashes.contains(hash)
        }
    }
}

extension KaspaWalletManager: ThenProcessable { }

extension KaspaWalletManager: DustRestrictable {
    var dustValue: Amount {
        Amount(with: wallet.blockchain, value: Decimal(0.2))
    }
}

extension KaspaWalletManager: WithdrawalNotificationProvider {
    // Chia, kaspa have the same logic
    @available(*, deprecated, message: "Use MaximumAmountRestrictable")
    func validateWithdrawalWarning(amount: Amount, fee: Amount) -> WithdrawalWarning? {
        let amountAvailableToSend = txBuilder.availableAmount() - fee
        if amount <= amountAvailableToSend {
            return nil
        }
        
        let amountToReduceBy = amount - amountAvailableToSend
        
        return WithdrawalWarning(
            warningMessage: "common_utxo_validate_withdrawal_message_warning".localized(
                [wallet.blockchain.displayName, txBuilder.maxInputCount, amountAvailableToSend.description]
            ),
            reduceMessage: "common_ok".localized,
            suggestedReduceAmount: amountToReduceBy
        )
    }
    
    func withdrawalNotification(amount: Amount, fee: Fee) -> WithdrawalNotification? {
        // The 'Mandatory amount change' withdrawal suggestion has been superseded by a validation performed in
        // the 'MaximumAmountRestrictable.validateMaximumAmount(amount:fee:)' method below
        return nil
    }
}

extension KaspaWalletManager: MaximumAmountRestrictable {
    func validateMaximumAmount(amount: Amount, fee: Amount) throws {
        let amountAvailableToSend = txBuilder.availableAmount() - fee
        if amount <= amountAvailableToSend {
            return
        }

        throw ValidationError.maximumUTXO(
            blockchainName: wallet.blockchain.displayName,
            newAmount: amountAvailableToSend,
            maxUtxo: txBuilder.maxInputCount
        )
    }
}
