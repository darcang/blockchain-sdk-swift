//
//  TronWalletManager.swift
//  BlockchainSdk
//
//  Created by Andrey Chukavin on 24.03.2022.
//  Copyright © 2022 Tangem AG. All rights reserved.
//

import Foundation
import Combine
import TangemSdk
import web3swift

class TronWalletManager: BaseManager, WalletManager {
    var networkService: TronNetworkService!
    var txBuilder: TronTransactionBuilder!
    
    var currentHost: String {
        networkService.host
    }
    
    var allowsFeeSelection: Bool {
        false
    }
    
    private let feeSigner = DummySigner()
    
    func update(completion: @escaping (Result<Void, Error>) -> Void) {
        let transactionIDs = wallet.transactions
            .filter { $0.status == .unconfirmed }
            .compactMap { $0.hash }
        
        cancellable = networkService.accountInfo(for: wallet.address, tokens: cardTokens, transactionIDs: transactionIDs)
            .sink { [unowned self] in
                switch $0 {
                case .failure(let error):
                    self.wallet.clearAmounts()
                    completion(.failure(error))
                case .finished:
                    completion(.success(()))
                }
            } receiveValue: { [unowned self] in
                self.updateWallet($0)
            }
    }
    
    func send(_ transaction: Transaction, signer: TransactionSigner) -> AnyPublisher<TransactionSendResult, Error> {
        return signedTransactionData(amount: transaction.amount, source: wallet.address, destination: transaction.destinationAddress, signer: signer, publicKey: wallet.publicKey)
            .flatMap { [weak self] data -> AnyPublisher<TronBroadcastResponse, Error> in
                guard let self = self else {
                    return .anyFail(error: WalletError.empty)
                }
                
                return self.networkService.broadcastHex(data)
            }
            .tryMap { [weak self] broadcastResponse -> TransactionSendResult in
                guard broadcastResponse.result == true else {
                    throw WalletError.failedToSendTx
                }
                
                var submittedTransaction = transaction
                submittedTransaction.hash = broadcastResponse.txid
                self?.wallet.transactions.append(submittedTransaction)
                
                return TransactionSendResult(hash: broadcastResponse.txid)
            }
            .eraseToAnyPublisher()
    }
    
    func getFee(amount: Amount, destination: String) -> AnyPublisher<[Fee], Error> {
        let energyUsePublisher: AnyPublisher<Int, Error>

        switch amount.type {
        case .reserve:
            return .anyFail(error: WalletError.failedToGetFee)
        case .coin:
            energyUsePublisher = Just(0).setFailureType(to: Error.self).eraseToAnyPublisher()
        case .token(let token):
            let addressData = TronAddressService.toByteForm(destination)?.padLeft(length: 32) ?? Data()
            guard let bigIntValue = Web3.Utils.parseToBigUInt("\(amount.value)", decimals: token.decimalCount) else {
                return .anyFail(error: WalletError.failedToGetFee)
            }
            
            let amountData = bigIntValue.serialize().padLeft(length: 32)
            let parameter = (addressData + amountData).hex
            
            energyUsePublisher = networkService.contractEnergyUsage(
                sourceAddress: wallet.address,
                contractAddress: token.contractAddress,
                parameter: parameter
            )
        }
        
        let transactionDataPublisher = signedTransactionData(
            amount: amount,
            source: wallet.address,
            destination: destination,
            signer: feeSigner,
            publicKey: feeSigner.publicKey
        )

        let blockchain = self.wallet.blockchain
        
        return Publishers.Zip(energyUsePublisher, networkService.chainParameters())
            .zip(networkService.accountExists(address: destination), transactionDataPublisher, networkService.getAccountResource(for: wallet.address))
            .map { (networkParameters, destinationExists, transactionData, resources) -> [Fee] in
                let (energyUse, chainParameters) = networkParameters
                
                if !destinationExists && amount.type == .coin {
                    let amount = Amount(with: blockchain, value: 1.1)
                    return [Fee(amount)]
                }

                let sunPerBandwidthPoint = 1000

                let dynamicEnergyMaxFactorPrecision: Double = 10_000
                let dynamicEnergyMaxFactor = Double(chainParameters.dynamicEnergyMaxFactor) / dynamicEnergyMaxFactorPrecision

                let additionalDataSize = 64
                let transactionSizeFee = sunPerBandwidthPoint * (transactionData.count + additionalDataSize)

                let sunPerEnergyUnit = chainParameters.sunPerEnergyUnit
                let maxEnergyFee = Int(ceil(Double(energyUse * sunPerEnergyUnit) * (1 + dynamicEnergyMaxFactor)))

                let totalFee = transactionSizeFee + maxEnergyFee

                let remainingBandwidthInSun = (resources.freeNetLimit - (resources.freeNetUsed ?? 0)) * sunPerBandwidthPoint

                if totalFee <= remainingBandwidthInSun {
                    return [Fee(.zeroCoin(for: blockchain))]
                } else {
                    let value = Decimal(totalFee) / blockchain.decimalValue
                    let amount = Amount(with: blockchain, value: value)
                    return [Fee(amount)]
                }
            }
            .eraseToAnyPublisher()
    }
    
    private func signedTransactionData(amount: Amount, source: String, destination: String, signer: TransactionSigner, publicKey: Wallet.PublicKey) -> AnyPublisher<Data, Error> {
        return networkService.getNowBlock()
            .tryMap { [weak self] block -> Protocol_Transaction.raw in
                guard let self = self else {
                    throw WalletError.empty
                }
                
                return try self.txBuilder.buildForSign(amount: amount, source: source, destination: destination, block: block)
            }
            .flatMap { [weak self] transactionRaw -> AnyPublisher<Data, Error> in
                guard let self = self else {
                    return .anyFail(error: WalletError.empty)
                }
                
                return Just(())
                    .setFailureType(to: Error.self)
                    .flatMap { [weak self] _ -> AnyPublisher<Data, Error> in
                        guard let self = self else {
                            return .anyFail(error: WalletError.empty)
                        }
                        
                        return self.sign(transactionRaw, with: signer, publicKey: publicKey)
                    }
                    .tryMap { [weak self] signature -> Protocol_Transaction in
                        guard let self = self else {
                            throw WalletError.empty
                        }
                        
                        return self.txBuilder.buildForSend(rawData: transactionRaw, signature: signature)
                    }
                    .tryMap {
                        try $0.serializedData()
                    }
                    .eraseToAnyPublisher()
            }
            
            .eraseToAnyPublisher()
    }
    
    private func sign(_ transactionRaw: Protocol_Transaction.raw, with signer: TransactionSigner, publicKey: Wallet.PublicKey) -> AnyPublisher<Data, Error> {
        Just(())
            .setFailureType(to: Error.self)
            .tryMap {
                try transactionRaw.serializedData().sha256()
            }
            .flatMap { hash -> AnyPublisher<Data, Error> in
                Just(hash)
                    .setFailureType(to: Error.self)
                    .flatMap {
                        signer.sign(hash: $0, walletPublicKey: publicKey)
                    }
                    .tryMap { [weak self] signature -> Data in
                        guard let self = self else {
                            throw WalletError.empty
                        }
                        
                        return self.unmarshal(signature, hash: hash, publicKey: publicKey)
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    private func updateWallet(_ accountInfo: TronAccountInfo) {
        wallet.add(amount: Amount(with: wallet.blockchain, value: accountInfo.balance))
        
        for (token, balance) in accountInfo.tokenBalances {
            wallet.add(tokenValue: balance, for: token)
        }
        
        for (index, transaction) in wallet.transactions.enumerated() {
            if let hash = transaction.hash, accountInfo.confirmedTransactionIDs.contains(hash) {
                wallet.transactions[index].status = .confirmed
            }
        }
    }
    
    private func unmarshal(_ signatureData: Data, hash: Data, publicKey: Wallet.PublicKey) -> Data {
        guard publicKey != feeSigner.publicKey else {
            return signatureData + Data(0)
        }
        
        do {
            let signature = try Secp256k1Signature(with: signatureData)
            let components = try signature.unmarshal(with: publicKey.blockchainKey, hash: hash)
            
            return components.r + components.s + components.v
        } catch {
            Log.error(error)
            return Data()
        }
    }
}

extension TronWalletManager: ThenProcessable {}


fileprivate class DummySigner: TransactionSigner {
    let privateKey: Data
    let publicKey: Wallet.PublicKey
    
    init() {
        let keyPair = try! Secp256k1Utils().generateKeyPair()
        let compressedPublicKey = try! Secp256k1Key(with: keyPair.publicKey).compress()
        self.publicKey = Wallet.PublicKey(seedKey: compressedPublicKey, derivedKey: nil, derivationPath: nil)
        self.privateKey = keyPair.privateKey
    }
        
    func sign(hash: Data, walletPublicKey: Wallet.PublicKey) -> AnyPublisher<Data, Error> {
        do {
            let signature = try Secp256k1Utils().sign(hash, with: privateKey)
            return Just(signature)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        } catch {
            return .anyFail(error: error)
        }
    }
    
    func sign(hashes: [Data], walletPublicKey: Wallet.PublicKey) -> AnyPublisher<[Data], Error> {
        fatalError()
    }
}
