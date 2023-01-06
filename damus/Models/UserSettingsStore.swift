//
//  UserSettingsStore.swift
//  damus
//
//  Created by Suhail Saqan on 12/29/22.
//

import Foundation

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
    
    @Published var default_image_host: ImageHost {
        didSet {
            UserDefaults.standard.set(default_image_host.rawValue, forKey: "default_image_host")
        }
    }

    init() {
        if let defaultWalletName = UserDefaults.standard.string(forKey: "default_wallet"),
           let default_wallet = Wallet(rawValue: defaultWalletName) {
            self.default_wallet = default_wallet
        } else {
            self.default_wallet = .system_default_wallet
        }
        if let defaultImageHostName = UserDefaults.standard.string(forKey: "default_image_host"),
           let default_image_host = ImageHost(rawValue: defaultImageHostName) {
            self.default_image_host = default_image_host
        } else {
            self.default_image_host = .nostrimg
        }
        self.show_wallet_selector = UserDefaults.standard.object(forKey: "show_wallet_selector") as? Bool ?? true
    }
}
