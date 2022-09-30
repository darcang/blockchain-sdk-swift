//
//  ContractInteractor.swift
//  BlockchainSdk
//
//  Created by Alexander Osokin on 30.09.2022.
//  Copyright © 2022 Tangem AG. All rights reserved.
//

import Foundation
import web3swift

public class ContractInteractor {
    private let address: String
    private let abi: String
    private let rpcURL: URL
    private let decimals: Int
    
    private lazy var defaultOptions: TransactionOptions = { .defaultOptions }()
    
    public init(address: String, abi: String, rpcURL: URL, decimals: Int = 18) {
        self.address = address
        self.abi = abi
        self.rpcURL = rpcURL
        self.decimals = decimals
    }
    
    public func read(method: String, parameters: [AnyObject], completion: @escaping (Result<Any, Error>) -> Void) {
        do {
            let contract = try makeContract()
            let transaction = try makeTransaction(from: contract, method: method, parameters: parameters, type: .read)
            call(transaction: transaction, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }
    
    public func write(method: String, parameters: [AnyObject], completion: @escaping (Result<Any, Error>) -> Void) {
        do {
            let contract = try makeContract()
            let transaction = try makeTransaction(from: contract, method: method, parameters: parameters, type: .write)
            call(transaction: transaction, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }
    
    private func makeContract() throws -> web3.web3contract {
        let web3 = try Web3.new(rpcURL)
        
        guard let address = EthereumAddress(self.address) else {
            throw ContractInteractorError.parseAddressFailed
        }
        
        guard let contract = web3.contract(abi, at: address, abiVersion: 2) else {
            throw ContractInteractorError.contractCreateFailed
        }
        
        return contract
    }
    
    private func makeTransaction(from contract: web3.web3contract,
                                 method: String,
                                 parameters: [AnyObject],
                                 type: TransactionType) throws  -> ReadTransaction {
        
        guard let transaction = type.isRead ? contract.read(method, parameters: parameters) :
                contract.write(method, parameters: parameters) else {
            throw ContractInteractorError.txCreateFailed
        }
        
        return transaction
    }
    
    private func call(transaction: ReadTransaction, completion: @escaping (Result<Any, Error>) -> Void) {
        let transactionOptions = defaultOptions
        
        DispatchQueue.global().async {
            do {
                let result = try transaction.call(transactionOptions: transactionOptions)
                
                guard let resultValue = result["0"] else {
                    throw ContractInteractorError.getResultFailed
                }
                
                completion(.success(resultValue))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

extension ContractInteractor {
    enum TransactionType {
        case read
        case write
        
        var isRead: Bool {
            switch self {
            case .read:
                return true
            case .write:
                return false
            }
        }
    }
}

public enum ContractInteractorError: String, Error, LocalizedError {
    case parseAddressFailed
    case contractCreateFailed
    case txCreateFailed
    case getResultFailed
    
    public var errorDescription: String? {
        self.rawValue
    }
}
