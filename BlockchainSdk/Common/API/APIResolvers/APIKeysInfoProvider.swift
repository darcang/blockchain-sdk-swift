//
//  APIKeysInfoProvider.swift
//  BlockchainSdk
//
//  Created by Andrew Son on 16/04/24.
//  Copyright © 2024 Tangem AG. All rights reserved.
//

import Foundation

struct APIKeysInfoProvider {
    let blockchain: Blockchain
    let config: BlockchainSdkConfig

    func apiKeys(for providerType: NetworkProviderType?) -> APIHeaderKeyInfo? {
        switch providerType {
        case .nowNodes:
            return NowNodesAPIKeysInfoProvider(apiKey: config.nowNodesApiKey)
                .apiKeys(for: blockchain)
        case .arkhiaHedera:
            return .init(
                headerName: Constants.xApiKeyHeaderName,
                headerValue: config.hederaArkhiaApiKey
            )
        case .ton:
            return .init(
                headerName: Constants.xApiKeyHeaderName,
                headerValue: config.tonCenterApiKeys.getApiKey(for: blockchain.isTestnet)
            )
        case .tron:
            return .init(
                headerName: "TRON-PRO-API-KEY",
                headerValue: config.tronGridApiKey
            )
        case .tangemChia:
            return .init(
                headerName: Constants.xApiKeyHeaderName,
                headerValue: config.chiaTangemApiKeys.mainnetApiKey
            )
        case .fireAcademy:
            return .init(
                headerName: Constants.xApiKeyHeaderName,
                headerValue: config.fireAcademyApiKeys.getApiKey(for: blockchain.isTestnet)
            )
        case .public, .quickNode, .getBlock, .blockchair, .blockcypher, .infura, .adalite, .tangemRosetta, .solana, .kaspa, .none:
            return nil
        }
    }
}
