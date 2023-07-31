//
//  EthereumChildWalletAssembly.swift
//  BlockchainSdk
//
//  Created by skibinalexander on 08.02.2023.
//  Copyright © 2023 Tangem AG. All rights reserved.
//

import Foundation
import TangemSdk
import stellarsdk
import BitcoinCore

struct EthereumWalletAssembly: WalletManagerAssembly {
    
    func make(with input: WalletManagerAssemblyInput) throws -> WalletManager {
        return try EthereumWalletManager(wallet: input.wallet).then {
            let chainId = input.blockchain.chainId!
            
            let blockcypherProvider: BlockcypherNetworkProvider?
            
            if case .ethereum = input.blockchain {
                blockcypherProvider = BlockcypherNetworkProvider(
                    endpoint: .ethereum,
                    tokens: input.blockchainConfig.blockcypherTokens,
                    configuration: input.networkConfig
                )
            } else {
                blockcypherProvider = nil
            }
            
            var blockscoutNetworkProvider: BlockscoutNetworkProvider?
            if input.blockchain.canLoadTransactionHistory {
                blockscoutNetworkProvider = networkProviderAssembly.makeBlockscoutNetworkProvider(
                    with: input
                )
            }
            
            $0.txBuilder = try EthereumTransactionBuilder(walletPublicKey: input.wallet.publicKey.blockchainKey, chainId: chainId)
            $0.networkService = EthereumNetworkService(
                decimals: input.blockchain.decimalCount,
                providers: networkProviderAssembly.makeEthereumJsonRpcProviders(with: input),
                blockcypherProvider: blockcypherProvider,
                blockchairProvider: nil, // TODO: TBD Do we need the TokenFinder feature?
                blockscoutNetworkProvider: blockscoutNetworkProvider,
                abiEncoder: WalletCoreABIEncoder()
            )
        }
    }
    
}
