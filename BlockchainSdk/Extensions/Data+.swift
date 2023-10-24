//
//  Data+.swift
//  BlockchainSdk
//
//  Created by Alexander Osokin on 13.12.2019.
//  Copyright © 2019 Tangem AG. All rights reserved.
//

import Foundation
import CryptoKit
import TangemSdk
import class WalletCore.DataVector

extension Data {
    public func aligned(to length: Int = 32) -> Data {
        let bytesCount = self.count
        
        guard bytesCount < length else {
            return self
        }
        
        let prefix = Data(repeating: 0, count: 32 - bytesCount)
        
        return prefix + self
    }
    
    func validateAsEdKey() throws {
        _ = try Curve25519.Signing.PublicKey(rawRepresentation: self)
    }
    
    func validateAsSecp256k1Key() throws {
        _ = try Secp256k1Key(with: self)
    }

    func leadingZeroPadding(toLength newLength: Int) -> Data {
        guard count < newLength else { return self }

        let prefix = Data(repeating: UInt8(0), count: newLength - count)
        return prefix + self
    }
    
    func trailingZeroPadding(toLength newLength: Int) -> Data {
        guard count < newLength else { return self }

        let suffix = Data(repeating: UInt8(0), count: newLength - count)
        return self + suffix
    }

    func asDataVector() -> DataVector {
        return DataVector(data: self)
    }
}
