//
//  Wallet.swift
//  damus
//
//  Created by Benjamin Hakes on 12/29/22.
//

import Foundation

// New url prefixes needed to be added to LSApplicationQueriesSchemes
enum Wallet: String, CaseIterable {
    
    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var index: Int
        var tag: String
        var displayName : String
        var link : String
        var appStoreLink : String
        var image: String
    }
    
    case systemdefaultwallet
    case strike
    case cashapp
    case muun
    case bluewallet
    case walletofsatoshi
    case zebedee
    case zeusln
    case lnlink
    case phoenix
    
    var model: Model {
        switch self {
        case .systemdefaultwallet:
            return .init(index: -1, tag: "systemdefaultwallet", displayName: "Local default",
                         link: "lightning:", appStoreLink: "lightning:", image: "")
        case .strike:
            return .init(index: 0, tag: "strike", displayName: "Strike", link: "strike:",
                         appStoreLink: "https://apps.apple.com/us/app/strike-bitcoin-payments/id1488724463", image: "strike")
        case .cashapp:
            return .init(index: 1, tag: "cashapp", displayName: "Cash App", link: "squarecash://",
                         appStoreLink: "https://apps.apple.com/us/app/cash-app/id711923939", image: "cashapp")
        case .muun:
            return .init(index: 2, tag: "muun", displayName: "Muun", link: "muun:", appStoreLink: "https://apps.apple.com/us/app/muun-wallet/id1482037683", image: "muun")
        case .bluewallet:
            return .init(index: 3, tag: "bluewallet", displayName: "Blue Wallet", link: "bluewallet:lightning:",
                         appStoreLink: "https://apps.apple.com/us/app/bluewallet-bitcoin-wallet/id1376878040", image: "bluewallet")
        case .walletofsatoshi:
            return .init(index: 4, tag: "walletofsatoshi", displayName: "Wallet Of Satoshi", link:  "walletofsatoshi:lightning:",
                         appStoreLink: "https://apps.apple.com/us/app/wallet-of-satoshi/id1438599608", image: "walletofsatoshi")
        case .zebedee:
            return .init(index: 5, tag: "zebedee", displayName: "Zebedee", link: "zebedee:lightning:",
                         appStoreLink: "https://apps.apple.com/us/app/zebedee-wallet/id1484394401", image: "zebedee")
        case .zeusln:
            return .init(index: 6, tag: "zeusln", displayName: "Zeus LN", link: "zeusln:lightning:",
                         appStoreLink: "https://apps.apple.com/us/app/zeus-ln/id1456038895", image: "zeusln")
        case .lnlink:
            return .init(index: 7, tag: "lnlink", displayName: "LNLink", link: "lnlink:lightning:",
                         appStoreLink: "https://testflight.apple.com/join/aNY4yuuZ", image: "lnlink")
        case .phoenix:
            return .init(index: 8, tag: "phoenix", displayName: "Phoenix", link: "phoenix://",
                         appStoreLink: "https://apps.apple.com/us/app/phoenix-wallet/id1544097028", image: "phoenix")
        }
    }
    
    static var allModels: [Model] {
        return Self.allCases.map { $0.model }
    }
}
