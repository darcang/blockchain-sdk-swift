//
//  SolanaEd25519Slip0010Tests.swift
//  BlockchainSdkTests
//
//  Created by Sergey Balashov on 25.08.2023.
//  Copyright © 2023 Tangem AG. All rights reserved.
//

import XCTest
import Combine

@testable import BlockchainSdk
@testable import Solana_Swift

private let raisedError = SolanaError.other("Just tx size test")

final class SolanaEd25519Slip0010Tests: XCTestCase {
    private class CoinSigner: TransactionSigner {
        private let sizeTester = TransactionSizeTesterUtility()
        
        func sign(hashes: [Data], walletPublicKey: BlockchainSdk.Wallet.PublicKey) -> AnyPublisher<[Data], Error> {
            sizeTester.testTxSizes(hashes)
            return Fail(error: raisedError)
                .eraseToAnyPublisher()
        }
        
        func sign(hash: Data, walletPublicKey: BlockchainSdk.Wallet.PublicKey) -> AnyPublisher<Data, Error> {
            sizeTester.testTxSize(hash)
            return Fail(error: raisedError)
                .eraseToAnyPublisher()
        }
    }
    
    private class TokenSigner: TransactionSigner {
        private let sizeTester = TransactionSizeTesterUtility()
        
        func sign(hashes: [Data], walletPublicKey: BlockchainSdk.Wallet.PublicKey) -> AnyPublisher<[Data], Error> {
            hashes.forEach {
                _ = sign(hash: $0, walletPublicKey: walletPublicKey)
            }
            return Fail(error: raisedError)
                .eraseToAnyPublisher()
        }
        
        func sign(hash: Data, walletPublicKey: BlockchainSdk.Wallet.PublicKey) -> AnyPublisher<Data, Error> {
            XCTAssertTrue(sizeTester.isValidForCos4_52AndAbove(hash))
            XCTAssertFalse(sizeTester.isValidForCosBelow4_52(hash))
            XCTAssertFalse(sizeTester.isValidForiPhone7(hash))
            return Fail(error: raisedError)
                .eraseToAnyPublisher()
        }
    }
    
    private var networkingRouter: NetworkingRouter!
    private var solanaSdk: Solana!
    private var manager: SolanaWalletManager!
    
    private var bag = Set<AnyCancellable>()
    
    private let network: RPCEndpoint = .devnetSolana
    private let walletPubKey = Data(hex: "B148CC30B144E8F214AE5754C753C40A9BF2A3359DB4246E03C6A2F61A82C282")
    private let address = "Cw3YcfqzRSa7xT7ecpR5E4FKDQU6aaxz5cWje366CZbf"
    private let blockchain = Blockchain.solana(curve: .ed25519_slip0010, testnet: false)
    
    private let coinSigner = CoinSigner()
    private let tokenSigner = TokenSigner()
    
    override func setUp() {
        super.setUp()
        networkingRouter = .init(endpoints: [.devnetSolana, .devnetGenesysGo, .testnetSolana])
        solanaSdk = .init(router: networkingRouter, accountStorage: SolanaDummyAccountStorage())
        let service = AddressServiceFactory(blockchain: blockchain).makeAddressService()

        let addrs = try! service.makeAddress(from: walletPubKey)
        let wallet = Wallet(blockchain: blockchain, addresses: [.default: addrs])

        manager = .init(wallet: wallet)
        manager.solanaSdk = solanaSdk
        manager.networkService = SolanaNetworkService(solanaSdk: solanaSdk, blockchain: blockchain, hostProvider: networkingRouter)
    }
    
    func testCoinTransactionSize() {
        let transaction = Transaction(
            amount: .zeroCoin(for: blockchain),
            fee: Fee(.zeroCoin(for: blockchain)),
            sourceAddress: manager.wallet.address,
            destinationAddress: "BmAzxn8WLYU3gEw79ATUdSUkMT53MeS5LjapBQB8gTPJ",
            changeAddress: manager.wallet.address,
            contractAddress: nil
        )

        let expected = expectation(description: "Waiting for response")
        
        processResult(manager.send(transaction, signer: coinSigner), expectationToFill: expected)
        waitForExpectations(timeout: 10)
    }
    
    func testTokenTransactionSize() {
        let type: Amount.AmountType = .token(
            value: .init(name: "Solanax",
                         symbol: "SOLD",
                         contractAddress: "5v6tZ1SiAi7G8Qg4rBF1ZdAn4cn6aeQtefewMr1NLy61",
                         decimalCount: 9)
        )
        let transaction = Transaction(
            amount: Amount(with: blockchain, type: type, value: 0),
            fee: Fee(Amount(with: blockchain, type: type, value: 0)),
            sourceAddress: manager.wallet.address,
            destinationAddress: "BmAzxn8WLYU3gEw79ATUdSUkMT53MeS5LjapBQB8gTPJ",
            changeAddress: manager.wallet.address
        )
        let expected = expectation(description: "Waiting for response")
        
        processResult(manager.send(transaction, signer: tokenSigner), expectationToFill: expected)
        waitForExpectations(timeout: 10)
    }
    
    private func processResult(_ publisher: AnyPublisher<TransactionSendResult, Error>, expectationToFill: XCTestExpectation) {
        bag.insert(
            publisher.sink(receiveCompletion: { completion in
                defer {
                    expectationToFill.fulfill()
                }
                
                guard case .failure(let error) = completion else {
                    XCTFail("Wrong complition received")
                    return
                }
                
                guard let castedError = error as? SolanaError else {
                    XCTFail("Wrong error returned from manager")
                    return
                }
                
                XCTAssertEqual(castedError, raisedError)
            }, receiveValue: { _ in
                XCTFail("Test shouldn't receive value")
            })
        )
    }
}