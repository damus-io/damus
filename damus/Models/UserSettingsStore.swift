//
//  UserSettingsStore.swift
//  damus
//
//  Created by Suhail Saqan on 12/29/22.
//

import Foundation

func should_show_wallet_selector(_ pubkey: String) -> Bool {
    return UserDefaults.standard.object(forKey: "show_wallet_selector") as? Bool ?? true
}

func get_default_wallet(_ pubkey: String) -> Wallet {
    if let defaultWalletName = UserDefaults.standard.string(forKey: "default_wallet"),
       let default_wallet = Wallet(rawValue: defaultWalletName)
    {
        return default_wallet
    } else {
        return .system_default_wallet
    }
}

class UserSettingsStore: ObservableObject {
    @Published var default_wallet: Wallet {
        didSet {
            UserDefaults.standard.set(default_wallet.rawValue, forKey: "default_wallet")
        }
    }
    
    @Published var show_wallet_selector: Bool {
        didSet {
            UserDefaults.standard.set(show_wallet_selector, forKey: "show_wallet_selector")
        }
    }

    @Published var left_handed: Bool {
        didSet {
            UserDefaults.standard.set(left_handed, forKey: "left_handed")
        }
    }

    init() {
        // TODO: pubkey-scoped settings
        let pubkey = ""
        self.default_wallet = get_default_wallet("")
        show_wallet_selector = should_show_wallet_selector("")

        left_handed = UserDefaults.standard.object(forKey: "left_handed") as? Bool ?? false
    }
}
