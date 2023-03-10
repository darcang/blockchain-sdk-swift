//
//  TONWalletManager.swift
//  BlockchainSdk
//
//  Created by skibinalexander on 12.01.2023.
//  Copyright © 2023 Tangem AG. All rights reserved.
//

import Foundation
import Combine
import TangemSdk
import WalletCore

final class TONWalletManager: BaseManager, WalletManager {
    
    // MARK: - Properties
    
    var currentHost: String { networkService.host }
    var allowsFeeSelection: Bool { false }
    
    // MARK: - Private Properties

    private let networkService: TONNetworkService
    private let txBuilder: TONTransactionBuilder
    private var isAvailable: Bool = true
    
    // MARK: - Init
    
    init(wallet: Wallet, networkService: TONNetworkService) throws {
        self.networkService = networkService
        self.txBuilder = .init(wallet: wallet)
        super.init(wallet: wallet)
    }
    
    // MARK: - Implementation
    
    func update(completion: @escaping (Result<Void, Error>) -> Void) {
        cancellable = networkService
            .getInfo(address: wallet.address)
            .sink(
                receiveCompletion: { [unowned self] completionSubscription in
                    if case let .failure(error) = completionSubscription {
                        self.wallet.amounts = [:]
                        self.isAvailable = false
                        completion(.failure(error))
                    }
                },
                receiveValue: { [unowned self] info in
                    self.update(by: info, completion: completion)
                }
            )
    }
    
    func send(_ transaction: Transaction, signer: TransactionSigner) -> AnyPublisher<TransactionSendResult, Error> {
        Just(())
            .receive(on: DispatchQueue.global())
            .tryMap { [weak self] _ -> String in
                guard let self = self else {
                    throw WalletError.failedToBuildTx
                }
                
                let input = try self.txBuilder.buildForSign(amount: transaction.amount, destination: transaction.destinationAddress)
                return try self.buildTransaction(input: input, with: signer)
            }
            .flatMap { [weak self] message -> AnyPublisher<String, Error> in
                guard let self = self else {
                    return Fail(error: WalletError.failedToBuildTx).eraseToAnyPublisher()
                }
                
                return self.networkService.send(message: message)
            }
            .map { [weak self] hash in
                self?.wallet.add(transaction: transaction)
                return TransactionSendResult(hash: hash)
            }
            .eraseToAnyPublisher()
    }
    
    func getFee(amount: Amount, destination: String) -> AnyPublisher<[Amount], Error> {
        guard isAvailable else {
            return Just(()).tryMap { _ in
                return [
                    Amount.zeroCoin(for: wallet.blockchain)
                ]
            }
            .eraseToAnyPublisher()
        }
        
        return Just(())
            .tryMap { [weak self] _ -> String in
                guard let self = self else {
                    throw WalletError.failedToBuildTx
                }
                
                let input = try self.txBuilder.buildForSign(amount: amount, destination: destination)
                return try self.buildTransaction(input: input)
            }
            .flatMap { [weak self] message -> AnyPublisher<[Amount], Error> in
                guard let self = self else {
                    return Fail(error: WalletError.failedToBuildTx).eraseToAnyPublisher()
                }
                
                return self.networkService.getFee(address: self.wallet.address, message: message)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Implementation
    
    private func update(by info: TONWalletInfo, completion: @escaping (Result<Void, Error>) -> Void) {
        wallet.add(coinValue: info.balance)
        txBuilder.sequenceNumber = info.sequenceNumber
        isAvailable = info.isAvailable
        completion(.success(()))
    }
    
    private func buildTransaction(input: TheOpenNetworkSigningInput, with signer: TransactionSigner? = nil) throws -> String {
        let output: TheOpenNetworkSigningOutput!
        
        if let signer = signer {
            let coreSigner = WalletCoreSigner(sdkSigner: signer, walletPublicKey: self.wallet.publicKey)
            
            if let error = coreSigner.error {
                throw error
            }
            
            output = AnySigner.signExternally(input: input, coin: .ton, signer: coreSigner)
        } else {
            output = AnySigner.sign(input: input, coin: .ton)
        }
        
        return try self.txBuilder.buildForSend(output: output)
    }
    
}
