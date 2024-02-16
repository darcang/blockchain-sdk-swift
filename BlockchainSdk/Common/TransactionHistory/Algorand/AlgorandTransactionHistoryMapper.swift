//
//  AlgorandTransactionHistoryMapper.swift
//  BlockchainSdk
//
//  Created by skibinalexander on 22.01.2024.
//  Copyright © 2024 Tangem AG. All rights reserved.
//

import Foundation
import TangemSdk

struct AlgorandTransactionHistoryMapper {
    private let blockchain: Blockchain
    
    init(blockchain: Blockchain) {
        self.blockchain = blockchain
    }
}

extension AlgorandTransactionHistoryMapper {
    func mapToTransactionRecords(
        _ items: [AlgorandTransactionHistory.Response.Item],
        amountType: Amount.AmountType,
        currentWalletAddress: String
    ) -> [TransactionRecord] {
        items.compactMap {
            guard 
                let id = $0.id,
                let paymentTransaction = $0.paymentTransaction
            else { return nil }
            
            let decimalFeeValue = Decimal($0.fee) / blockchain.decimalValue
            let decimalAmountValue = Decimal(paymentTransaction.amount) / blockchain.decimalValue
            
            return TransactionRecord(
                hash: id,
                source: .single(
                    .init(address: $0.sender, amount: decimalAmountValue)
                ),
                destination: .single(
                    .init(address: .user(paymentTransaction.receiver), amount: decimalAmountValue)
                ),
                fee: .init(.init(with: blockchain, value: decimalFeeValue)),
                status: .confirmed,
                isOutgoing: $0.sender.lowercased() == currentWalletAddress.lowercased() ,
                type: .transfer,
                date: $0.roundTime
            )
        }
    }
}
