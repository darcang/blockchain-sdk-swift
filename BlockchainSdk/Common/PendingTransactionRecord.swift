//
//  PendingTransactionRecord.swift
//  BlockchainSdk
//
//  Created by Sergey Balashov on 04.10.2023.
//  Copyright © 2023 Tangem AG. All rights reserved.
//

import Foundation

public struct PendingTransactionRecord {
    public let hash: String
    public let source: String
    public let destination: String
    public let amount: Amount
    public let fee: Fee
    public let date: Date
    public let isIncoming: Bool
    public let transactionParams: TransactionParams?
    
    public var isDummy: Bool {
        hash == .unknown || source == .unknown || destination == .unknown
    }
    
    public init(
        hash: String,
        source: String,
        destination: String,
        amount: Amount,
        fee: Fee,
        date: Date,
        isIncoming: Bool,
        transactionParams: TransactionParams? = nil
    ) {
        self.hash = hash
        self.source = source
        self.destination = destination
        self.amount = amount
        self.fee = fee
        self.date = date
        self.isIncoming = isIncoming
        self.transactionParams = transactionParams
    }
}
