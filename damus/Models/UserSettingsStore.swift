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
            UserDefaults.standard.set(defaultWallet.rawValue, forKey: "default_wallet")
        }
    }
    
    @Published var showWalletSelector: Bool {
        didSet {
            UserDefaults.standard.set(showWalletSelector, forKey: "show_wallet_selector")
        }
    }

    init() {
        if let defaultWalletName = UserDefaults.standard.string(forKey: "default_wallet"),
           let defaultWallet = Wallet(rawValue: defaultWalletName) {
            self.defaultWallet = defaultWallet
        } else {
            self.defaultWallet = .systemdefaultwallet
        }
        self.showWalletSelector = UserDefaults.standard.object(forKey: "show_wallet_selector") as? Bool ?? true
    }
}
