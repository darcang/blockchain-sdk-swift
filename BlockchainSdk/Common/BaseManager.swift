//
//  BaseManager.swift
//  BlockchainSdk
//
//  Created by Alexander Osokin on 05.03.2022.
//  Copyright © 2022 Tangem AG. All rights reserved.
//

import Foundation
import Combine

@available(iOS 13.0, *)
class BaseManager: WalletProvider {
    @Published var wallet: Wallet
    var cardTokens: [Token] = []
    
    var defaultSourceAddress: String { wallet.address }
    var defaultChangeAddress: String { wallet.address }
    
    var cancellable: Cancellable? = nil
    var walletPublisher: Published<Wallet>.Publisher { $wallet }

    init(wallet: Wallet) {
        self.wallet = wallet
    }
    
    func removeToken(_ token: Token) {
        cardTokens.removeAll(where: { $0 == token })
        wallet.remove(token: token)
    }
    
    func addToken(_ token: Token) {
        if !cardTokens.contains(token) {
            cardTokens.append(token)
        }
    }
    
    func addTokens(_ tokens: [Token]) {
        tokens.forEach { addToken($0) }
    }
}

// MARK: - TransactionBuilder

extension BaseManager: TransactionBuilder {
    func createTransaction(
        amount: Amount,
        fee: Amount,
        destinationAddress: String,
        sourceAddress: String?,
        contractAddress: String?,
        changeAddress: String?
    ) throws -> Transaction {
        let transaction = Transaction(
            amount: amount,
            fee: fee,
            sourceAddress: sourceAddress ?? defaultSourceAddress,
            destinationAddress: destinationAddress,
            changeAddress: changeAddress ?? defaultChangeAddress,
            contractAddress: contractAddress ?? amount.type.token?.contractAddress,
            date: Date(),
            status: .unconfirmed,
            hash: nil
        )
        
        try validateTransaction(amount: amount, fee: fee)
        return transaction
    }
    
    func validate(amount: Amount) -> TransactionError? {
        if !validateAmountValue(amount) {
            return .invalidAmount
        }
        
        if !validateAmountTotal(amount) {
            return .amountExceedsBalance
        }
        
        return nil
    }
    
    func validate(fee: Amount) -> TransactionError? {
        if !validateAmountValue(fee) {
            return .invalidFee
        }
        
        if !validateAmountTotal(fee) {
            return .feeExceedsBalance
        }
        
        return nil
    }
}

// MARK: - Validation

private extension BaseManager {
    func validateTransaction(amount: Amount, fee: Amount?) throws {
        var errors = [TransactionError]()
        
        let amountError = validate(amount: amount)
        
        guard let fee = fee else {
            errors.appendIfNotNil(amountError)
            throw TransactionErrors(errors: errors)
        }
        
        errors.appendIfNotNil(validate(fee: fee))
        errors.appendIfNotNil(amountError)
                
        let total = amount + fee
        
        if amount.type == fee.type, total.value > 0,
            validate(amount: total) != nil {
            errors.append(.totalExceedsBalance)
        }
        
        if let dustAmount = (self as? DustRestrictable)?.dustValue {
            if amount < dustAmount {
                errors.append(.dustAmount(minimumAmount: dustAmount))
            }
            
            if let walletAmount = wallet.amounts[dustAmount.type] {
                let change = walletAmount - total
                if change.value != 0 && change < dustAmount {
                    errors.append(.dustChange(minimumAmount: dustAmount))
                }
            }
        }
        
        if let minimumBalanceRestrictable = self as? MinimumBalanceRestrictable,
           let walletAmount = wallet.amounts[amount.type],
           case .coin = amount.type
        {
            let remainderBalance = walletAmount - total
            if remainderBalance < minimumBalanceRestrictable.minimumBalance && !remainderBalance.isZero {
                errors.append(.minimumBalance(minimumBalance: minimumBalanceRestrictable.minimumBalance))
            }
        }
        
        if !errors.isEmpty {
            throw TransactionErrors(errors: errors)
        }
    }
    
    func validateAmountValue(_ amount: Amount) -> Bool {
        return amount.value >= 0
    }
    
    func validateAmountTotal(_ amount: Amount) -> Bool {
        let total = wallet.amounts[amount.type] ?? Amount(with: amount, value: 0)
        
        guard total >= amount else {
            return false
        }
        
        return true
    }
}
