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
            UserDefaults.standard.set(defaultWallet.rawValue, forKey: "defaultwallet")
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
