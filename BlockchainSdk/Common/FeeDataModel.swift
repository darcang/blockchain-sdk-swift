//
//  FeeType.swift
//  BlockchainSdk
//
//  Created by Sergey Balashov on 15.03.2023.
//  Copyright © 2023 Tangem AG. All rights reserved.
//

import Foundation

public protocol FeeParameters {}

public enum FeeType {
    case single(fee: FeeModel)
    case multiple(low: FeeModel, normal: FeeModel, priority: FeeModel)
  
    public init(feeType: FeeType) {
        self.feeType = feeType
    }
    
    public init(fees: [Amount]) throws {
        switch fees.count {
            /// User hasn't a choice
        case 1:
            self.feeType = .single(fee: FeeModel(fees[0]))
            /// User has a choice of 3 option
        case 3:
            self.feeType = .multiple(low: FeeModel(fees[0]), normal: FeeModel(fees[1]), priority: FeeModel(fees[2]))
        default:
            assertionFailure("FeeType can't be created")
            throw BlockchainSdkError.failedToLoadFee
        }
    }

    public init(fees: [FeeModel]) throws {
        switch fees.count {
        /// User hasn't a choice
        case 1:
            self.feeType = .single(fee: fees[0])
        /// User has a choice of 3 option
        case 3:
            self.feeType = .multiple(low: fees[0], normal: fees[1], priority: fees[2])
        default:
            assertionFailure("FeeType can't be created")
            throw BlockchainSdkError.failedToLoadFee
        }
    }
}

// MARK: - Helpers

public extension FeeType {
    static func zero(blockchain: Blockchain) -> FeeType {
        FeeType(feeType: .single(fee: FeeModel(.zeroCoin(for: blockchain))))
    }
    
    var asArray: [Amount] {
        switch feeType {
        case .multiple(let low, let normal, let priority):
            return [low.fee, normal.fee, priority.fee]
            
        case .single(let fee):
            return [fee.fee]
        }
    }
    
    var lowFeeModel: FeeModel? {
        if case .multiple(let fee, _, _) = feeType {
            return fee
        }

        return nil
    }
    
    var normalFeeModel: FeeModel? {
        if case .multiple(_, let normal, _) = feeType {
            return normal
        }

        return nil
    }
    
    var priorityFeeModel: FeeModel? {
        if case .multiple(_, _, let priority) = feeType {
            return priority
        }

        return nil
    }
    
    var lowFee: Amount? {
        if case .multiple(let fee, _, _) = feeType {
            return fee.fee
        }

        return nil
    }
    
    var normalFee: Amount? {
        if case .multiple(_, let normal, _) = feeType {
            return normal.fee
        }

        return nil
    }
    
    var priorityFee: Amount? {
        if case .multiple(_, _, let priority) = feeType {
            return priority.fee
        }

        return nil
    }
}

// MARK: - FeeType

public extension FeeType {
    struct FeeModel {
        let fee: Amount
        let parameters: FeeParameters?
        
        init(_ fee: Amount, parameters: FeeParameters? = nil) {
            self.fee = fee
            self.parameters = parameters
        }
    }
}

extension FeeType: CustomStringConvertible {
    public var description: String {
        "FeeType: \(feeType.description)"
    }
}
