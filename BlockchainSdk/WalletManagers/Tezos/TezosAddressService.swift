//
//  TezosAddressService.swift
//  BlockchainSdk
//
//  Created by Alexander Osokin on 19.10.2020.
//  Copyright © 2020 Tangem AG. All rights reserved.
//

import Foundation
import Sodium
import stellarsdk
import TangemSdk

@available(iOS 13.0, *)
public struct TezosAddressService {
    private let curve: EllipticCurve
    
    init(curve: EllipticCurve) {
        self.curve = curve
    }
}

// MARK: - AddressProvider

@available(iOS 13.0, *)
extension TezosAddressService: AddressProvider {
    public func makeAddress(for publicKey: Wallet.PublicKey, with addressType: AddressType) throws -> AddressPublicKeyPair {
        var key: Data
        switch curve {
        case .ed25519:
            try publicKey.blockchainKey.validateAsEdKey()
            key = publicKey.blockchainKey
        case .secp256k1:
            key = try Secp256k1Key(with: publicKey.blockchainKey).compress()
        case .secp256r1:
            fatalError("Not implemented")
        default:
            fatalError("Unsupported curve")
        }
        let publicKeyHash = Sodium().genericHash.hash(message: key.bytes, outputLength: 20)!
        let prefix = TezosPrefix.addressPrefix(for: curve)
        let prefixedHash = prefix + publicKeyHash
        let checksum = prefixedHash.sha256().sha256().prefix(4)
        let prefixedHashWithChecksum = prefixedHash + checksum
        let address = Base58.encode(prefixedHashWithChecksum)

        return AddressPublicKeyPair(value: address, publicKey: publicKey, type: addressType)
    }
}

// MARK: - AddressValidator

@available(iOS 13.0, *)
extension TezosAddressService: AddressValidator {
    public func validate(_ address: String) -> Bool {
        let prefixedHashWithChecksum = address.base58DecodedData
        guard prefixedHashWithChecksum.count == 27 else {
            return false
        }

        let prefixedHash = prefixedHashWithChecksum.prefix(23)
        let checksum = prefixedHashWithChecksum.suffix(from: 23)
        let calculatedChecksum = prefixedHash.sha256().sha256().prefix(4)
        return calculatedChecksum == checksum
    }
}
