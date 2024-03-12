//
//  RadiantNetworkUrl.swift
//  BlockchainSdk
//
//  Created by skibinalexander on 12.03.2024.
//  Copyright © 2024 Tangem AG. All rights reserved.
//

import Foundation

enum RadiantNetworkEndpoint: CaseIterable {
    case radiantForPeople
    
    var host: String {
        switch self {
        case .radiantForPeople:
            return "electrumx-01-ssl.radiant4people.com"
        }
    }
    
    var port: Int {
        switch self {
        case .radiantForPeople:
            return 51002
        }
    }
    
    var urlString: String {
        return "wss://\(host):\(port)"
    }
}
