//
//  UserSettingsStore.swift
//  damus
//
//  Created by Suhail Saqan on 12/29/22.
//

import Foundation
import Vault

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

    @Published var libretranslate_server: LibreTranslateServer {
        didSet {
            if oldValue == libretranslate_server {
                return
            }

            UserDefaults.standard.set(libretranslate_server.rawValue, forKey: "libretranslate_server")

            libretranslate_api_key = ""

            if libretranslate_server == .custom || libretranslate_server == .none {
                libretranslate_url = ""
            } else {
                libretranslate_url = libretranslate_server.model.url!
            }
        }
    }

    @Published var libretranslate_url: String {
        didSet {
            UserDefaults.standard.set(libretranslate_url, forKey: "libretranslate_url")
        }
    }

    @Published var libretranslate_api_key: String {
        didSet {
            do {
                if libretranslate_api_key == "" {
                    try clearLibreTranslateApiKey()
                } else {
                    try saveLibreTranslateApiKey(libretranslate_api_key)
                }
            } catch {
                // No-op.
            }
        }
    }

    init() {
        if let defaultWalletName = UserDefaults.standard.string(forKey: "default_wallet"),
           let default_wallet = Wallet(rawValue: defaultWalletName)
        {
            self.default_wallet = default_wallet
        } else {
            default_wallet = .system_default_wallet
        }
        show_wallet_selector = UserDefaults.standard.object(forKey: "show_wallet_selector") as? Bool ?? true

        left_handed = UserDefaults.standard.object(forKey: "left_handed") as? Bool ?? false

        if let translationServerName = UserDefaults.standard.string(forKey: "libretranslate_server"),
           let translationServer = LibreTranslateServer(rawValue: translationServerName) {
            self.libretranslate_server = translationServer
            libretranslate_url = translationServer.model.url ?? UserDefaults.standard.object(forKey: "libretranslate_url") as? String ?? ""
        } else {
            // Note from @tyiu:
            // Default server is disabled by default for now until we gain some confidence that it is working well in production.
            // Instead of throwing all Damus users onto feature immediately, allow for discovery of feature organically.
            // Also, we are connecting to servers listed as mirrors on the official LibreTranslate GitHub README that do not require API keys.
            // However, we have not asked them for permission to use, so we're trying to be good neighbors for now.
            // Opportunity: spin up dedicated trusted LibreTranslate server that requires an API key for any access (or higher rate limit access).
            libretranslate_server = .none
            libretranslate_url = ""
        }

        do {
            libretranslate_api_key = try Vault.getPrivateKey(keychainConfiguration: DamusLibreTranslateKeychainConfiguration())
        } catch {
            libretranslate_api_key = ""
        }
    }

    func saveLibreTranslateApiKey(_ apiKey: String) throws {
        try Vault.savePrivateKey(apiKey, keychainConfiguration: DamusLibreTranslateKeychainConfiguration())
    }

    func clearLibreTranslateApiKey() throws {
        try Vault.deletePrivateKey(keychainConfiguration: DamusLibreTranslateKeychainConfiguration())
    }
}

struct DamusLibreTranslateKeychainConfiguration: KeychainConfiguration {
    var serviceName = "damus"
    var accessGroup: String? = nil
    var accountName = "libretranslate_apikey"
}
