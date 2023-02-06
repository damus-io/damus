//
//  Wallet.swift
//  damus
//
//  Created by Benjamin Hakes on 12/29/22.
//

import Foundation

enum Wallet: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var index: Int
        var tag: String
        var displayName : String
        var link : String
        var appStoreLink : String?
        var image: String
    }
    
    // New url prefixes needed to be added to LSApplicationQueriesSchemes
    case system_default_wallet
    case strike
    case cashapp
    case muun
    case bluewallet
    case walletofsatoshi
    case zebedee
    case zeusln
    case lnlink
    case phoenix
    case breez
    case bitcoinbeach
    case blixtwallet
    case river
    
    var model: Model {
        switch self {
        case .system_default_wallet:
            return .init(index: -1, tag: "systemdefaultwallet", displayName: NSLocalizedString("Local default", comment: "Dropdown option label for system default for Lightning wallet."),
                         link: "lightning:", appStoreLink: "lightning:", image: "")
        case .strike:
            return .init(index: 0, tag: "strike", displayName: NSLocalizedString("Strike", comment: "Dropdown option label for Lightning wallet, Strike."), link: "strike:",
                         appStoreLink: "https://apps.apple.com/us/app/strike-bitcoin-payments/id1488724463", image: "strike")
        case .cashapp:
            return .init(index: 1, tag: "cashapp", displayName: NSLocalizedString("Cash App", comment: "Dropdown option label for Lightning wallet, Cash App."), link: "https://cash.app/launch/lightning/",
                         appStoreLink: "https://apps.apple.com/us/app/cash-app/id711923939", image: "cashapp")
        case .muun:
            return .init(index: 2, tag: "muun", displayName: NSLocalizedString("Muun", comment: "Dropdown option label for Lightning wallet, Muun."), link: "muun:", appStoreLink: "https://apps.apple.com/us/app/muun-wallet/id1482037683", image: "muun")
        case .bluewallet:
            return .init(index: 3, tag: "bluewallet", displayName: NSLocalizedString("Blue Wallet", comment: "Dropdown option label for Lightning wallet, Blue Wallet."), link: "bluewallet:lightning:",
                         appStoreLink: "https://apps.apple.com/us/app/bluewallet-bitcoin-wallet/id1376878040", image: "bluewallet")
        case .walletofsatoshi:
            return .init(index: 4, tag: "walletofsatoshi", displayName: NSLocalizedString("Wallet of Satoshi", comment: "Dropdown option label for Lightning wallet, Wallet of Satoshi."), link:  "walletofsatoshi:lightning:",
                         appStoreLink: "https://apps.apple.com/us/app/wallet-of-satoshi/id1438599608", image: "walletofsatoshi")
        case .zebedee:
            return .init(index: 5, tag: "zebedee", displayName: NSLocalizedString("Zebedee", comment: "Dropdown option label for Lightning wallet, Zebedee."), link: "zebedee:lightning:",
                         appStoreLink: "https://apps.apple.com/us/app/zebedee-wallet/id1484394401", image: "zebedee")
        case .zeusln:
            return .init(index: 6, tag: "zeusln", displayName: NSLocalizedString("Zeus LN", comment: "Dropdown option label for Lightning wallet, Zeus LN."), link: "zeusln:lightning:",
                         appStoreLink: "https://apps.apple.com/us/app/zeus-ln/id1456038895", image: "zeusln")
        case .lnlink:
            return .init(index: 7, tag: "lnlink", displayName: NSLocalizedString("LNLink", comment: "Dropdown option label for Lightning wallet, LNLink."), link: "lnlink:lightning:",
                         appStoreLink: "https://testflight.apple.com/join/aNY4yuuZ", image: "lnlink")
        case .phoenix:
            return .init(index: 8, tag: "phoenix", displayName: NSLocalizedString("Phoenix", comment: "Dropdown option label for Lightning wallet, Phoenix."), link: "phoenix://",
                         appStoreLink: "https://apps.apple.com/us/app/phoenix-wallet/id1544097028", image: "phoenix")
        case .breez:
            return .init(index: 9, tag: "breez", displayName: NSLocalizedString("Breez", comment: "Dropdown option label for Lightning wallet, Breez."), link: "breez:",
                         appStoreLink: "https://apps.apple.com/us/app/breez-lightning-client-pos/id1463604142", image: "breez")
        case .bitcoinbeach:
            return .init(index: 10, tag: "bitcoinbeach", displayName: NSLocalizedString("Bitcoin Beach", comment: "Dropdown option label for Lightning wallet, Bitcoin Beach."), link: "bitcoinbeach://",
                         appStoreLink: "https://apps.apple.com/sv/app/bitcoin-beach-wallet/id1531383905", image: "bbw")
        case .blixtwallet:
            return .init(index: 11, tag: "blixtwallet", displayName: NSLocalizedString("Blixt Wallet", comment: "Dropdown option label for Lightning wallet, Blixt Wallet"), link: "blixtwallet:lightning:",
                         appStoreLink: "https://testflight.apple.com/join/EXvGhRzS", image: "blixt-wallet")
        case .river:
            return .init(index: 12, tag: "river", displayName: NSLocalizedString("River", comment: "Dropdown option label for Lightning wallet, River"), link: "river://",
                         appStoreLink: "https://apps.apple.com/us/app/river-buy-mine-bitcoin/id1536176542", image: "river")
            
        }
    }
    
    static var allModels: [Model] {
        return Self.allCases.map { $0.model }
    }
}
