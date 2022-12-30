//
//  UserSettings.swift
//  damus
//
//  Created by Suhail Saqan on 12/29/22.
//

import Foundation

struct WalletItem : Decodable, Identifiable, Hashable {
    var id: Int
    var tag: String
    var name : String
    var link : String
    var appStoreLink : String
    var image: String
}

// New url prefixes needed to be added to LSApplicationQueriesSchemes
enum Wallet: String, CaseIterable {
    case defaultwallet = """
    {"id": -1, "tag": "defaultwallet", "name": "Local default", "link": "lightning:", "appStoreLink": "lightning:", "image": ""}
    """
    case strike = """
    {"id": 0, "tag": "strike", "name": "Strike", "link": "strike:", "appStoreLink": "https://apps.apple.com/us/app/strike-bitcoin-payments/id1488724463", "image": "strike"}
    """
    case cashapp = """
    {"id": 1, "tag": "cashapp", "name": "Cash App", "link": "squarecash://", "appStoreLink": "https://apps.apple.com/us/app/cash-app/id711923939", "image": "cashapp"}
    """
    case muun = """
    {"id": 2, "tag": "muun", "name": "Muun", "link": "muun:", "appStoreLink": "https://apps.apple.com/us/app/muun-wallet/id1482037683", "image": "muun"}
    """
    case bluewallet = """
    {"id": 3, "tag": "bluewallet", "name": "Blue Wallet", "link": "bluewallet:lightning:", "appStoreLink": "https://apps.apple.com/us/app/bluewallet-bitcoin-wallet/id1376878040", "image": "bluewallet"}
    """
    case walletofsatoshi = """
    {"id": 4, "tag": "walletofsatoshi", "name": "Wallet Of Satoshi", "link": "walletofsatoshi:lightning:", "appStoreLink": "https://apps.apple.com/us/app/wallet-of-satoshi/id1438599608", "image": "walletofsatoshi"}
    """
    case zebedee = """
    {"id": 5, "tag": "zebedee", "name": "Zebedee", "link": "zebedee:lightning:", "appStoreLink": "https://apps.apple.com/us/app/zebedee-wallet/id1484394401", "image": "zebedee"}
    """
    case zeusln = """
    {"id": 6, "tag": "zeusln", "name": "Zeus LN", "link": "zeusln:lightning:", "appStoreLink": "https://apps.apple.com/us/app/zeus-ln/id1456038895", "image": "zeusln"}
    """
    case lnlink = """
    {"id": 7, "tag": "lnlink", "name": "LNLink", "link": "lnlink:lightning:", "appStoreLink": "https://testflight.apple.com/join/aNY4yuuZ", "image": "lnlink"}
    """
    case phoenix = """
    {"id": 8, "tag": "phoenix", "name": "Phoenix", "link": "phoenix://", "appStoreLink": "https://apps.apple.com/us/app/phoenix-wallet/id1544097028", "image": "phoenix"}
    """
}

class UserSettingsStore: ObservableObject {
    @Published var defaultwallet: Wallet {
        didSet {
            UserDefaults.standard.set(defaultwallet.rawValue, forKey: "defaultwallet")
        }
    }
    
    @Published var showwalletselector: Bool {
        didSet {
            UserDefaults.standard.set(showwalletselector, forKey: "showwalletselector")
        }
    }

    init() {
        self.defaultwallet = (UserDefaults.standard.object(forKey: "defaultwallet") == nil ? Wallet.defaultwallet : Wallet(rawValue: UserDefaults.standard.object(forKey: "defaultwallet") as! String)) ?? Wallet.defaultwallet
        self.showwalletselector = UserDefaults.standard.object(forKey: "showwalletselector") == nil ? true : UserDefaults.standard.object(forKey: "showwalletselector") as! Bool
    }
}

func get_wallet_list() -> [WalletItem] {
    let values: [String] = Wallet.allCases.map { $0.rawValue }

    var walletList: [WalletItem] = []

    for value in values {
        let data = value.data(using: .utf8)!
        do {
            let wallet = try JSONDecoder().decode(WalletItem.self, from: data)
            walletList.append(wallet)
        } catch {
            return []
        }
    }
    return walletList
}

func get_wallet_tag(_ tag: String) -> Wallet {
    switch tag {
    case "defaultwallet":
        return Wallet.defaultwallet
    case "strike":
        return Wallet.strike
    case "cashapp":
        return Wallet.cashapp
    case "muun":
        return Wallet.muun
    case "bluewallet":
        return Wallet.bluewallet
    case "walletofsatoshi":
        return Wallet.walletofsatoshi
    case "zebedee":
        return Wallet.zebedee
    case "zeusln":
        return Wallet.zeusln
    case "lnlink":
        return Wallet.lnlink
    case "phoenix":
        return Wallet.phoenix
    default:
        return Wallet.defaultwallet
    }
}

func get_default_wallet(_ us: String) -> WalletItem {
    let data = us.data(using: .utf8)!
    do {
        return try JSONDecoder().decode(WalletItem.self, from: data)
    } catch {
        return get_wallet_list()[0]
    }
    
}
