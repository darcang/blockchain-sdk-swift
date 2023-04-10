//
//  CosmosRestProvider.swift
//  BlockchainSdk
//
//  Created by Andrey Chukavin on 10.04.2023.
//  Copyright © 2023 Tangem AG. All rights reserved.
//

import Foundation
import Combine
import Moya

class CosmosRestProvider: HostProvider {
    let url: URL
    
    var host: String {
        url.hostOrUnknown
    }
    
    private let provider: NetworkProvider<CosmosTarget>
    
    init(url: String, configuration: NetworkProviderConfiguration) {
        self.url = URL(string: url)!
        provider = NetworkProvider<CosmosTarget>(configuration: configuration)
    }
    
    func accounts(address: String) -> AnyPublisher<CosmosAccountResponse, Error> {
        requestPublisher(for: .accounts(address: address))
    }
    
    func balances(address: String) -> AnyPublisher<CosmosBalanceResponse, Error> {
        requestPublisher(for: .balances(address: address))
    }
    
    func simulate(data: Data) -> AnyPublisher<CosmosSimulateResponse, Error> {
        requestPublisher(for: .simulate(data: data))
    }
    
    func txs(data: Data) -> AnyPublisher<CosmosTxResponse, Error> {
        requestPublisher(for: .txs(data: data))
    }
    
    private func requestPublisher<T: Decodable>(for target: CosmosTarget.CosmosTargetType) -> AnyPublisher<T, Error> {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return provider.requestPublisher(CosmosTarget(baseURL: url, type: target))
            .filterSuccessfulStatusAndRedirectCodes()
            .map(T.self, using: decoder)
            .mapError { moyaError in
                if case .objectMapping = moyaError {
                    return WalletError.failedToParseNetworkResponse
                }
                return moyaError
            }
            .eraseToAnyPublisher()
    }
}
