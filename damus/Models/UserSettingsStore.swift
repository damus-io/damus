//
//  UserSettingsStore.swift
//  damus
//
//  Created by Suhail Saqan on 12/29/22.
//

import Foundation

class UserSettingsStore: ObservableObject {
    @Published var defaultWallet: Wallet {
        didSet {
            UserDefaults.standard.set(defaultWallet.rawValue, forKey: "systemdefaultwallet")
        }
    }
    
    @Published var showWalletSelector: Bool {
        didSet {
            UserDefaults.standard.set(showWalletSelector, forKey: "showwalletselector")
        }
    }

    init() {
        self.defaultWallet = UserDefaults.standard.object(forKey: "defaultwallet") as? Wallet ?? .systemdefaultwallet
        self.showWalletSelector = UserDefaults.standard.object(forKey: "showwalletselector") as? Bool ?? true
    }
}
//
//func get_wallet_list() -> [WalletItem] {
//    let values: [String] = Wallet.allCases.map { $0.rawValue }
//
//    var walletList: [WalletItem] = []
//
//    for value in values {
//        let data = value.data(using: .utf8)!
//        do {
//            let wallet = try JSONDecoder().decode(WalletItem.self, from: data)
//            walletList.append(wallet)
//        } catch {
//            return []
//        }
//    }
//    return walletList
//}

//func get_wallet_tag(_ tag: String) -> Wallet {
//    switch tag {
//    case "defaultwallet":
//        return Wallet.defaultwallet
//    case "strike":
//        return Wallet.strike
//    case "cashapp":
//        return Wallet.cashapp
//    case "muun":
//        return Wallet.muun
//    case "bluewallet":
//        return Wallet.bluewallet
//    case "walletofsatoshi":
//        return Wallet.walletofsatoshi
//    case "zebedee":
//        return Wallet.zebedee
//    case "zeusln":
//        return Wallet.zeusln
//    case "lnlink":
//        return Wallet.lnlink
//    case "phoenix":
//        return Wallet.phoenix
//    default:
//        return Wallet.defaultwallet
//    }
//}

//func get_default_wallet(_ us: String) -> WalletItem {
//    let data = us.data(using: .utf8)!
//    do {
//        return try JSONDecoder().decode(WalletItem.self, from: data)
//    } catch {
//        return get_wallet_list()[0]
//    }
//
//}
