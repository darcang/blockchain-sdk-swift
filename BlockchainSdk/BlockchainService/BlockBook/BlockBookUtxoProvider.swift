//
//  BlockBookUtxoProvider.swift
//  BlockchainSdk
//
//  Created by Pavel Grechikhin on 18.11.2022.
//  Copyright © 2022 Tangem AG. All rights reserved.
//

import Foundation
import Combine

/// Documentation: https://github.com/trezor/blockbook/blob/master/docs/api.md
class BlockBookUtxoProvider {
    var host: String {
        "\(blockchain.currencySymbol.lowercased()).\(config.host)"
    }
    
    private let blockchain: Blockchain
    private let config: BlockBookConfig
    private let provider: NetworkProvider<BlockBookTarget>

    var decimalValue: Decimal {
        blockchain.decimalValue
    }
    
    init(blockchain: Blockchain, blockBookConfig: BlockBookConfig, networkConfiguration: NetworkProviderConfiguration) {
        self.blockchain = blockchain
        self.config = blockBookConfig
        self.provider = NetworkProvider<BlockBookTarget>(configuration: networkConfiguration)
    }
    
    func addressData(address: String, parameters: BlockBookTarget.AddressRequestParameters) -> AnyPublisher<BlockBookAddressResponse, Error> {
        provider
            .requestPublisher(target(for: .address(address: address, parameters: parameters)))
            .filterSuccessfulStatusAndRedirectCodes()
            .map(BlockBookAddressResponse.self)
            .eraseError()
            .eraseToAnyPublisher()
    }
    
    func unspentTxData(address: String) -> AnyPublisher<[BlockBookUnspentTxResponse], Error> {
        provider
            .requestPublisher(target(for: .utxo(address: address)))
            .filterSuccessfulStatusAndRedirectCodes()
            .map([BlockBookUnspentTxResponse].self)
            .eraseError()
            .eraseToAnyPublisher()
    }
    
    func getFeeRatePerByte(for confirmationBlocks: Int) -> AnyPublisher<Decimal, Error> {
        provider
            .requestPublisher(target(for: .fees(confirmationBlocks: confirmationBlocks)))
            .filterSuccessfulStatusAndRedirectCodes()
            .map(BlockBookFeeResponse.self)
            .tryMap { [weak self] response in
                guard let self else {
                    throw WalletError.empty
                }
                
                return try mapFee(Decimal(response.result.feerate))
            }
            .eraseToAnyPublisher()
    }
    
    func mapFee(_ fee: Decimal) throws -> Decimal {
        if fee <= 0 {
            throw BlockchainSdkError.failedToLoadFee
        }
        
        // estimatesmartfee returns fee in currency per kilobyte
        let bytesInKiloByte: Decimal = 1024
        let feeRatePerByte = fee * decimalValue / bytesInKiloByte
        
        return feeRatePerByte.rounded(roundingMode: .up)
    }
    
    func sendTransaction(hex: String) -> AnyPublisher<String, Error> {
        guard let transactionData = hex.data(using: .utf8) else {
            return .anyFail(error: WalletError.failedToSendTx)
        }
        
        return provider
            .requestPublisher(target(for: .send(tx: transactionData)))
            .filterSuccessfulStatusAndRedirectCodes()
            .map(BlockBookSendResponse.self)
            .eraseError()
            .map { $0.result }
            .eraseToAnyPublisher()
    }
    
    private func target(for request: BlockBookTarget.Request) -> BlockBookTarget {
        BlockBookTarget(request: request, config: config, blockchain: blockchain)
    }
}
