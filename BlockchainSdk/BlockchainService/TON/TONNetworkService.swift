//
//  TONNetworkService.swift
//  BlockchainSdk
//
//  Created by skibinalexander on 31.01.2023.
//  Copyright © 2023 Tangem AG. All rights reserved.
//

import Foundation
import Combine

/// Abstract layer for multi provide TON blockchain
class TONNetworkService: MultiNetworkProvider {
    
    // MARK: - Protperties
    
    let providers: [TONProvider]
    var currentProviderIndex: Int = 0
    
    private var blockchain: Blockchain
    
    // MARK: - Init
    
    init(providers: [TONProvider], blockchain: Blockchain) {
        self.providers = providers
        self.blockchain = blockchain
    }
    
    // MARK: - Implementation
    
    func getInfo(address: String) -> AnyPublisher<TONWalletInfo, Error> {
        providerPublisher { provider in
            provider
                .getInfo(address: address)
                .tryMap { [weak self] walletInfo in
                    guard let self = self else {
                        throw WalletError.empty
                    }
                    
                    guard let decimalBalance = Decimal(walletInfo.balance) else {
                        throw WalletError.failedToParseNetworkResponse
                    }
                    
                    return TONWalletInfo(
                        balance: decimalBalance / self.blockchain.decimalValue,
                        sequenceNumber: walletInfo.seqno ?? 0,
                        isAvailable: walletInfo.accountState == .active
                    )
                }
                .eraseToAnyPublisher()
        }
    }
    
    func getFee(address: String, message: String) -> AnyPublisher<[Amount], Error> {
        providerPublisher { provider in
            provider
                .getFee(address: address, body: message)
                .tryMap { [weak self] fee in
                    guard let self = self else {
                        throw WalletError.empty
                    }
                    
                    let fee = fee.sourceFees.totalFee / self.blockchain.decimalValue
                    return [Amount(with: self.blockchain, value: fee)]
                }
                .eraseToAnyPublisher()
        }
    }
    
    func send(message: String) -> AnyPublisher<String, Error> {
        return providerPublisher { provider in
            provider
                .send(message: message)
                .map(\.hash)
                .eraseToAnyPublisher()
        }
    }
    
}
