//
//  WalletManagerFactory.swift
//  BlockchainSdk
//
//  Created by Alexander Osokin on 06.12.2019.
//  Copyright © 2019 Tangem AG. All rights reserved.
//

import Foundation
import TangemSdk
import stellarsdk
import BitcoinCore

@available(iOS 13.0, *)
public class WalletManagerFactory {
    private let config: BlockchainSdkConfig
    
    public init(config: BlockchainSdkConfig) {
        self.config = config
    }
    
    /// Base wallet manager constructor
    /// - Parameters:
    ///   - card: Tangem card
    ///   - blockchain: blockhain to create. If nil, card native blockchain will be used
    /// - Returns: WalletManager?
    public func makeWalletManager(from cardId: String, walletPublicKey: Data, blockchain: Blockchain) -> WalletManager? {
        makeWalletManager(from: blockchain,
                          walletPublicKey: walletPublicKey,
                          cardId: cardId)
    }
    
    public func makeWalletManagers(from cardId: String, walletPublicKey: Data, blockchains: [Blockchain]) -> [WalletManager] {
        return blockchains.compactMap { makeWalletManager(from: cardId, walletPublicKey:walletPublicKey, blockchain: $0) }
    }
    
    public func makeEthereumWalletManager(from cardId: String, walletPublicKey: Data, erc20Tokens: [Token], isTestnet: Bool) -> WalletManager? {
        guard let manager = makeWalletManager(from: cardId, walletPublicKey: walletPublicKey, blockchain: .ethereum(testnet: isTestnet)) else {
            return nil
        }
        
        let additionalTokens = erc20Tokens.filter { !manager.cardTokens.contains($0) }
        manager.cardTokens.append(contentsOf: additionalTokens)
        return manager
    }
    
    public func makeTwinWalletManager(from cardId: String, walletPublicKey: Data, pairKey: Data, isTestnet: Bool) -> WalletManager? {
        makeWalletManager(from: .bitcoin(testnet: isTestnet),
                          walletPublicKey: walletPublicKey,
                          cardId: cardId,
                          walletPairPublicKey: pairKey,
                          tokens: [])
    }
    
    func makeWalletManager(from blockchain: Blockchain,
                           walletPublicKey: Data,
                           cardId: String,
                           walletPairPublicKey: Data? = nil,
                           tokens: [Token] = []) -> WalletManager? {
        
        if blockchain.curve == .ed25519, walletPublicKey.count > 32 { return nil } //wrong key
        
		let addresses = blockchain.makeAddresses(from: walletPublicKey, with: walletPairPublicKey)
		let wallet = Wallet(blockchain: blockchain,
                            addresses: addresses,
                            cardId: cardId,
                            publicKey: walletPublicKey)
         
        switch blockchain {
        case .bitcoin(let testnet):
            return BitcoinWalletManager(wallet: wallet).then {
                let network: BitcoinNetwork = testnet ? .testnet : .mainnet
                let bitcoinManager = BitcoinManager(networkParams: network.networkParams,
                                                             walletPublicKey: walletPublicKey,
                                                             compressedWalletPublicKey: Secp256k1Utils.convertKeyToCompressed(walletPublicKey)!,
                                                             bip: walletPairPublicKey == nil ? .bip84 : .bip141)
                
                $0.txBuilder = BitcoinTransactionBuilder(bitcoinManager: bitcoinManager, addresses: addresses)
                
                var providers = [BitcoinNetworkProvider]()
                providers.append(BlockchainInfoNetworkProvider())
                providers.append(BlockchairNetworkProvider(endpoint: .bitcoin, apiKey: config.blockchairApiKey))
                providers.append(BlockcypherNetworkProvider(endpoint: BlockcypherEndpoint(coin: .btc, chain: testnet ? .test3: .main),
                                                              tokens: config.blockcypherTokens))
                
                $0.networkService = BitcoinNetworkService(providers: providers)
            }
            
        case .litecoin:
            return LitecoinWalletManager(wallet: wallet).then {
                let bitcoinManager = BitcoinManager(networkParams: LitecoinNetworkParams(),
                                                    walletPublicKey: walletPublicKey,
                                                    compressedWalletPublicKey: Secp256k1Utils.convertKeyToCompressed(walletPublicKey)!,
                                                    bip: .bip44)
                
                $0.txBuilder = BitcoinTransactionBuilder(bitcoinManager: bitcoinManager, addresses: addresses)
                
                var providers = [BitcoinNetworkProvider]()
                providers.append(BlockchairNetworkProvider(endpoint: .litecoin, apiKey: config.blockchairApiKey))
                providers.append(BlockcypherNetworkProvider(endpoint: BlockcypherEndpoint(coin: .ltc, chain: .main), tokens: config.blockcypherTokens))

                $0.networkService = LitecoinNetworkService(providers: providers)
            }
            
        case .dogecoin:
            return DogecoinWalletManager(wallet: wallet).then {
                let bitcoinManager = BitcoinManager(networkParams: DogecoinNetworkParams(),
                                                    walletPublicKey: walletPublicKey,
                                                    compressedWalletPublicKey: Secp256k1Utils.convertKeyToCompressed(walletPublicKey)!,
                                                    bip: .bip44)
                
                $0.txBuilder = BitcoinTransactionBuilder(bitcoinManager: bitcoinManager, addresses: addresses)
                
                var providers = [BitcoinNetworkProvider]()
                providers.append(BlockchairNetworkProvider(endpoint: .dogecoin, apiKey: config.blockchairApiKey))
                providers.append(BlockcypherNetworkProvider(endpoint: BlockcypherEndpoint(coin: .doge, chain: .main), tokens: config.blockcypherTokens))

                $0.networkService = DogecoinNetworkService(providers: providers)
            }
            
        case .ducatus:
            return DucatusWalletManager(wallet: wallet).then {
                let bitcoinManager = BitcoinManager(networkParams: DucatusNetworkParams(), walletPublicKey: walletPublicKey, compressedWalletPublicKey: Secp256k1Utils.convertKeyToCompressed(walletPublicKey)!, bip: .bip44)
                
                $0.txBuilder = BitcoinTransactionBuilder(bitcoinManager: bitcoinManager, addresses: addresses)
                $0.networkService = DucatusNetworkService()
            }
            
        case .stellar(let testnet):
            return StellarWalletManager(wallet: wallet, cardTokens: tokens).then {
                let url = testnet ? "https://horizon-testnet.stellar.org" : "https://horizon.stellar.org"
                let stellarSdk = StellarSDK(withHorizonUrl: url)
                $0.stellarSdk = stellarSdk
                $0.txBuilder = StellarTransactionBuilder(stellarSdk: stellarSdk, walletPublicKey: walletPublicKey, isTestnet: testnet)
                $0.networkService = StellarNetworkService(stellarSdk: stellarSdk)
            }
            
        case .ethereum(let testnet):
            return EthereumWalletManager(wallet: wallet, cardTokens: tokens).then {
                let ethereumNetwork = testnet ? EthereumNetwork.testnet(projectId: config.infuraProjectId) : EthereumNetwork.mainnet(projectId: config.infuraProjectId)
                let jsonRpcProviders = [
                    EthereumJsonRpcProvider(network: ethereumNetwork),
                    EthereumJsonRpcProvider(network: .tangem)
                ]
                $0.txBuilder = EthereumTransactionBuilder(walletPublicKey: walletPublicKey, network: ethereumNetwork)
                let provider = BlockcypherNetworkProvider(endpoint: .init(coin: .eth, chain: .main), tokens: config.blockcypherTokens)
                let blockchair = BlockchairEthNetworkProvider(apiKey: config.blockchairApiKey)
                $0.networkService = EthereumNetworkService(network: ethereumNetwork, providers: jsonRpcProviders, blockcypherProvider: provider, blockchairProvider: blockchair)
            }
            
        case .rsk:
            return EthereumWalletManager(wallet: wallet, cardTokens: tokens).then {
                let network: EthereumNetwork = .rsk
                $0.txBuilder = EthereumTransactionBuilder(walletPublicKey: walletPublicKey, network: network)
                let blockchair = BlockchairEthNetworkProvider(apiKey: config.blockchairApiKey)
                $0.networkService = EthereumNetworkService(network: .rsk, providers: [EthereumJsonRpcProvider(network: network)], blockcypherProvider: nil, blockchairProvider: blockchair)
            }
            
        case .bsc(let testnet):
            return EthereumWalletManager(wallet: wallet).then {
                let network: EthereumNetwork = testnet ? .bscTestnet : .bscMainnet
                $0.txBuilder = EthereumTransactionBuilder(walletPublicKey: walletPublicKey, network: network)
                $0.networkService = EthereumNetworkService(network: network, providers: [EthereumJsonRpcProvider(network: network)], blockcypherProvider: nil, blockchairProvider: nil)
            }
            
        case .matic(let testnet):
            return EthereumWalletManager(wallet: wallet).then {
                let network: EthereumNetwork = testnet ? .maticTestnet : .maticMainnet
                $0.txBuilder = EthereumTransactionBuilder(walletPublicKey: walletPublicKey, network: network)
                $0.networkService = EthereumNetworkService(network: network, providers: [EthereumJsonRpcProvider(network: network)], blockcypherProvider: nil, blockchairProvider: nil)
            }
            
        case .bitcoinCash(let testnet):
            return BitcoinCashWalletManager(wallet: wallet).then {
                let provider = BlockchairNetworkProvider(endpoint: .bitcoinCash, apiKey: config.blockchairApiKey)
                $0.txBuilder = BitcoinCashTransactionBuilder(walletPublicKey: walletPublicKey, isTestnet: testnet)
                $0.networkService = BitcoinCashNetworkService(provider: provider)
            }
            
        case .binance(let testnet):
            return BinanceWalletManager(wallet: wallet, cardTokens: tokens).then {
                $0.txBuilder = BinanceTransactionBuilder(walletPublicKey: walletPublicKey, isTestnet: testnet)
                $0.networkService = BinanceNetworkService(isTestNet: testnet)
            }
            
        case .cardano(let shelley):
            return CardanoWalletManager(wallet: wallet).then {
                $0.txBuilder = CardanoTransactionBuilder(walletPublicKey: walletPublicKey, shelleyCard: shelley)
                let service = CardanoNetworkService(providers: [
                    AdaliteNetworkProvider(baseUrl: .main),
                    RosettaNetworkProvider(baseUrl: .tangemRosetta)
                ])
                $0.networkService = service
            }
            
        case .xrp(let curve):
            return XRPWalletManager(wallet: wallet).then {
                $0.txBuilder = XRPTransactionBuilder(walletPublicKey: walletPublicKey, curve: curve)
                $0.networkService = XRPNetworkService(providers: [XRPNetworkProvider(baseUrl: .main),
                                                                  XRPNetworkProvider(baseUrl: .reserve)])
            }
        case .tezos(let curve):
            return TezosWalletManager(wallet: wallet).then {
                $0.txBuilder = TezosTransactionBuilder(walletPublicKey: walletPublicKey, curve: curve)
                $0.networkService = TezosNetworkService()
            }
        }
    }
}
