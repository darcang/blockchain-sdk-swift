//
//  TONBlockchainFactory.swift
//  BlockchainSdk
//
//  Created by skibinalexander on 31.01.2023.
//  Copyright © 2023 Tangem AG. All rights reserved.
//

import Foundation
import Combine
import TangemSdk

struct TONBlockchainAssemblyFactory: BlockchainAssemblyFactoryProtocol {
    
    func canAssembly(blockchain: Blockchain) -> Bool {
        return blockchain == .ton(testnet: blockchain.isTestnet)
    }
    
    func assembly(with input: BlockchainAssemblyFactoryInput) throws -> AssemblyWallet {
        try TONWalletManager(
            wallet: input.wallet,
            networkService: .init(
                providers: TONNodeName.allCases.sorted().map {
                    TONProvider(
                        nodeName: $0,
                        config: input.blockchainConfig,
                        network: .init(configuration: input.networkConfig),
                        isTestnet: input.blockchain.isTestnet
                    )
                }.compactMap({$0}),
                blockchain: input.blockchain
            )
        )
    }
    
}
