//
//  Amount.swift
//  BlockchainSdk
//
//  Created by Alexander Osokin on 13.04.2020.
//  Copyright © 2020 Tangem AG. All rights reserved.
//

import Foundation
import BigInt
import web3swift

public struct Amount: CustomStringConvertible, Equatable, Comparable {
    public enum AmountType {
        case coin
        case token(value: Token)
        case reserve
        
        public var token: Token? {
            if case let .token(token) = self {
                return token
            }
            return nil
        }
        
        public var isToken: Bool {
            return token != nil
        }
    }
    
    public let type: AmountType
    public let currencySymbol: String
    public var value: Decimal
    public let decimals: Int

    public var bigUIntValue: BigUInt? {
        if isZero {
            return BigUInt.zero
        }
        
        if value == Decimal.greatestFiniteMagnitude {
            return BigUInt(2).power(256) - 1
        }

        return Web3.Utils.parseToBigUInt("\(value)", decimals: decimals)
    }
    
    public var encoded: Data? {
        guard let bigUIntValue = bigUIntValue else {
            return nil
        }
        
        let amountData = bigUIntValue.serialize()
        return amountData
    }
    
    public var encodedForSend: String? {
        if isZero {
            return "0x0"
        }
        
        return encoded?.hexString.stripLeadingZeroes().addHexPrefix()
    }
    
    /// For transaction data.
    public var encodedAligned: Data? {
        encoded?.aligned()
    }
    
    public var isZero: Bool {
        return value == 0
    }
    
    public var description: String {
        return string()
    }
    
    public init(with blockchain: Blockchain, type: AmountType = .coin, value: Decimal) {
        self.type = type
        currencySymbol = blockchain.currencySymbol
        decimals = blockchain.decimalCount
        self.value = value
    }
    
    public init(with token: Token, value: Decimal) {
        type = .token(value: token)
        currencySymbol = token.symbol
        decimals = token.decimalCount
        self.value = value
    }
    
    public init(with amount: Amount, value: Decimal) {
        type = amount.type
        currencySymbol = amount.currencySymbol
        decimals = amount.decimals
        self.value = value
    }
    
    public func string(with decimals: Int? = nil, roundingMode: NSDecimalNumber.RoundingMode = .down) -> String {
        let decimalsCount = decimals ?? self.decimals
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .currency
        formatter.usesGroupingSeparator = true
        formatter.currencySymbol = currencySymbol
        formatter.alwaysShowsDecimalSeparator = true
        formatter.maximumFractionDigits = decimalsCount
        formatter.minimumFractionDigits = 2
        let rounded = value.rounded(scale: decimalsCount, roundingMode: roundingMode)
        return formatter.string(from: rounded as NSDecimalNumber) ??
            "\(rounded) \(currencySymbol)"
    }
    
    public static func ==(lhs: Amount, rhs: Amount) -> Bool {
        if lhs.type != rhs.type {
            return false
        }
        
        return lhs.value == rhs.value
    }
    
    static public func -(l: Amount, r: Amount) -> Amount {
        if l.type != r.type {
            return l
        }
        return Amount(with: l, value: l.value - r.value)
    }
    
    static public func +(l: Amount, r: Amount) -> Amount {
        if l.type != r.type {
            return l
        }
        return Amount(with: l, value: l.value + r.value)
    }
    
    public static func < (lhs: Amount, rhs: Amount) -> Bool {
        if lhs.type != rhs.type {
            fatalError("Compared amounts must be the same type")
        }
        
        return lhs.value < rhs.value
    }
    
}
extension Amount.AmountType: Equatable, Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .coin:
            hasher.combine("coin")
        case .reserve:
            hasher.combine("reserve")
        case .token(let value):
            hasher.combine(value.hashValue)
        }
    }
    
    public static func == (lhs: Amount.AmountType, rhs: Amount.AmountType) -> Bool {
        switch (lhs, rhs) {
        case (.coin, .coin):
            return true
        case (.reserve, .reserve):
            return true
        case (.token(let lv), .token(let rv)):
            if lv.symbol == rv.symbol,
                lv.contractAddress == rv.contractAddress {
                return true
            }
            return false
        default:
            return false
        }
    }
}

extension Amount {
    static func dummyCoin(for blockchain: Blockchain) -> Amount {
        Amount(with: blockchain, type: .coin, value: 0)
    }
    
    public static func zeroCoin(for blockchain: Blockchain) -> Amount {
        .init(with: blockchain, type: .coin, value: 0)
    }
    
    public static func maxCoin(for blockchain: Blockchain) -> Amount {
        .init(with: blockchain, type: .coin, value: Decimal.greatestFiniteMagnitude)
    }
}
