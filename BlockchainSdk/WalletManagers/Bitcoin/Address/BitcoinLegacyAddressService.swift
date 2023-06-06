//
//  BitcoinLegacyAddressService.swift
//  BlockchainSdk
//
//  Created by Sergey Balashov on 06.06.2023.
//  Copyright © 2023 Tangem AG. All rights reserved.
//

import Foundation
import BitcoinCore

public class BitcoinLegacyAddressService {
    private let converter: IAddressConverter

    init(networkParams: INetwork) {
        converter = Base58AddressConverter(addressVersion: networkParams.pubKeyHash, addressScriptVersion: networkParams.scriptHash)
    }

    public func makeMultisigAddress(from scriptHash: Data) throws -> String {
        let address = try converter.convert(keyHash: scriptHash, type: .p2sh).stringValue

        return address
    }
}

// MARK: - AddressValidator

@available(iOS 13.0, *)
extension BitcoinLegacyAddressService: AddressValidator {
    public func validate(_ address: String) -> Bool {
        do {
            _ = try converter.convert(address: address)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - AddressProvider

@available(iOS 13.0, *)
extension BitcoinLegacyAddressService: AddressProvider {
    public func makeAddress(for publicKey: Wallet.PublicKey, with addressType: AddressType) throws -> AddressPublicKeyPair {
        try publicKey.blockchainKey.validateAsSecp256k1Key()

        let bitcoinCorePublicKey = PublicKey(withAccount: 0,
                                             index: 0,
                                             external: true,
                                             hdPublicKeyData: publicKey.blockchainKey)

        let address = try converter.convert(publicKey: bitcoinCorePublicKey, type: .p2pkh).stringValue
        return AddressPublicKeyPair(value: address, publicKey: publicKey, type: addressType)
    }
}
