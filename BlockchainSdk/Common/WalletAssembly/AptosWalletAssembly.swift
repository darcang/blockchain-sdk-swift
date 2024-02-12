//
//  AptosWalletAssembly.swift
//  BlockchainSdk
//
//  Created by skibinalexander on 25.01.2024.
//  Copyright © 2024 Tangem AG. All rights reserved.
//

import Foundation

struct AptosWalletAssembly: WalletManagerAssembly {
    func make(with input: WalletManagerAssemblyInput) throws -> WalletManager {
        let chainId: AptosChainId = input.blockchain.isTestnet ? .testnet : .mainnet        

        var providers: [AptosNetworkProvider] = [
            makeNetworkMainnetProvider(
                for: .nownodes,
                with: input.blockchainSdkConfig.nowNodesApiKey,
                networkConfig: input.networkConfig
            ),
            makeNetworkMainnetProvider(
                for: .getblock,
                with: input.blockchainSdkConfig.getBlockCredentials.credential(for: input.blockchain, type: .rest),
                networkConfig: input.networkConfig
            ),
            makeNetworkMainnetProvider(
                for: .aptoslabs,
                networkConfig: input.networkConfig
            )
        ]
        
        let txBuilder = AptosTransactionBuilder(
            publicKey: input.wallet.publicKey.blockchainKey,
            decimalValue: input.blockchain.decimalValue, 
            walletAddress: input.wallet.address,
            chainId: chainId
        )
        
        let networkService = AptosNetworkService(
            providers: providers,
            blockchain: input.blockchain
        )
        
        return AptosWalletManager(wallet: input.wallet, transactionBuilder: txBuilder, networkService: networkService)
    }
    
    // MARK: - Private Implementation
    
    private func makeNetworkMainnetProvider(
        for node: AptosProviderType,
        with apiKeyValue: String? = nil,
        networkConfig: NetworkProviderConfiguration
    ) -> AptosNetworkProvider {
        AptosNetworkProvider(
            node: .init(type: node, apiKeyValue: apiKeyValue),
            networkConfig: networkConfig
        )
    }
}
