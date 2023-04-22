//
//  UserSettingsStore.swift
//  damus
//
//  Created by Suhail Saqan on 12/29/22.
//

import Foundation
import Vault
import UIKit

let fallback_zap_amount = 1000

@propertyWrapper struct Setting<T: Equatable> {
    private let key: String
    private var value: T
    
    init(key: String, default_value: T) {
        self.key = pk_setting_key(UserSettingsStore.pubkey ?? "", key: key)
        if let loaded = UserDefaults.standard.object(forKey: self.key) as? T {
            self.value = loaded
        } else if let loaded = UserDefaults.standard.object(forKey: key) as? T {
            // try to load from deprecated non-pubkey-keyed setting
            self.value = loaded
        } else {
            self.value = default_value
        }
    }
    
    var wrappedValue: T {
        get { return value }
        set {
            guard self.value != newValue else {
                return
            }
            self.value = newValue
            UserDefaults.standard.set(newValue, forKey: key)
            UserSettingsStore.shared!.objectWillChange.send()
        }
    }
}

@propertyWrapper class StringSetting<T: StringCodable & Equatable> {
    private let key: String
    private var value: T
    
    init(key: String, default_value: T) {
        self.key = pk_setting_key(UserSettingsStore.pubkey ?? "", key: key)
        if let loaded = UserDefaults.standard.string(forKey: self.key), let val = T.init(from: loaded) {
            self.value = val
        } else if let loaded = UserDefaults.standard.string(forKey: key), let val = T.init(from: loaded) {
            // try to load from deprecated non-pubkey-keyed setting
            self.value = val
        } else {
            self.value = default_value
        }
    }
    
    var wrappedValue: T {
        get { return value }
        set {
            guard self.value != newValue else {
                return
            }
            self.value = newValue
            UserDefaults.standard.set(newValue.to_string(), forKey: key)
            UserSettingsStore.shared!.objectWillChange.send()
        }
    }
}

class UserSettingsStore: ObservableObject {
    static var pubkey: String? = nil
    static var shared: UserSettingsStore? = nil
    
    @StringSetting(key: "default_wallet", default_value: .system_default_wallet)
    var default_wallet: Wallet
    
    @StringSetting(key: "default_media_uploader", default_value: .nostrBuild)
    var default_media_uploader: MediaUploader
    
    @Setting(key: "show_wallet_selector", default_value: true)
    var show_wallet_selector: Bool
    
    @Setting(key: "left_handed", default_value: false)
    var left_handed: Bool
    
    @Setting(key: "always_show_images", default_value: false)
    var always_show_images: Bool

    @Setting(key: "zap_vibration", default_value: true)
    var zap_vibration: Bool
    
    @Setting(key: "zap_notification", default_value: true)
    var zap_notification: Bool
    
    @Setting(key: "default_zap_amount", default_value: fallback_zap_amount)
    var default_zap_amount: Int
    
    @Setting(key: "mention_notification", default_value: true)
    var mention_notification: Bool

    @Setting(key: "repost_notification", default_value: true)
    var repost_notification: Bool
    
    @Setting(key: "dm_notification", default_value: true)
    var dm_notification: Bool
    
    @Setting(key: "like_notification", default_value: true)
    var like_notification: Bool
    
    @Setting(key: "notification_only_from_following", default_value: false)
    var notification_only_from_following: Bool
    
    @Setting(key: "translate_dms", default_value: false)
    var translate_dms: Bool
    
    @Setting(key: "truncate_timeline_text", default_value: false)
    var truncate_timeline_text: Bool
    
    @Setting(key: "truncate_mention_text", default_value: true)
    var truncate_mention_text: Bool
    
    @Setting(key: "notification_indicators", default_value: NewEventsBits.all.rawValue)
    var notification_indicators: Int
    
    @Setting(key: "auto_translate", default_value: true)
    var auto_translate: Bool

    @Setting(key: "show_only_preferred_languages", default_value: false)
    var show_only_preferred_languages: Bool

    @Setting(key: "onlyzaps_mode", default_value: false)
    var onlyzaps_mode: Bool
    
    @Setting(key: "disable_animation", default_value: UIAccessibility.isReduceMotionEnabled)
    var disable_animation: Bool
    
    @StringSetting(key: "friend_filter", default_value: .all)
    var friend_filter: FriendFilter
    
    @StringSetting(key: "notification_state", default_value: .all)
    var notification_state: NotificationFilterState

    @StringSetting(key: "translation_service", default_value: .none)
    var translation_service: TranslationService

    @StringSetting(key: "deepl_plan", default_value: .free)
    var deepl_plan: DeepLPlan
    
    var deepl_api_key: String {
        didSet {
            do {
                if deepl_api_key == "" {
                    try clearDeepLApiKey()
                } else {
                    try saveDeepLApiKey(deepl_api_key)
                }
            } catch {
                // No-op.
            }
        }
    }

    @Setting(key: "libretranslate_server", default_value: .vern)
    var libretranslate_server: LibreTranslateServer
    
    @Setting(key: "libretranslate_url", default_value: "")
    var libretranslate_url: String

    @Setting(key: "libretranslate_api_key", default_value: "")
    var libretranslate_api_key: String {
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
        do {
            deepl_api_key = try Vault.getPrivateKey(keychainConfiguration: DamusDeepLKeychainConfiguration())
        } catch {
            deepl_api_key = ""
        }
    }

    private func saveLibreTranslateApiKey(_ apiKey: String) throws {
        try Vault.savePrivateKey(apiKey, keychainConfiguration: DamusLibreTranslateKeychainConfiguration())
    }

    private func clearLibreTranslateApiKey() throws {
        try Vault.deletePrivateKey(keychainConfiguration: DamusLibreTranslateKeychainConfiguration())
    }

    private func saveDeepLApiKey(_ apiKey: String) throws {
        try Vault.savePrivateKey(apiKey, keychainConfiguration: DamusDeepLKeychainConfiguration())
    }

    private func clearDeepLApiKey() throws {
        try Vault.deletePrivateKey(keychainConfiguration: DamusDeepLKeychainConfiguration())
    }

    func can_translate(_ pubkey: String) -> Bool {
        switch translation_service {
        case .none:
            return false
        case .libretranslate:
            return URLComponents(string: libretranslate_url) != nil
        case .deepl:
            return deepl_api_key != ""
        }
    }
}

struct DamusLibreTranslateKeychainConfiguration: KeychainConfiguration {
    var serviceName = "damus"
    var accessGroup: String? = nil
    var accountName = "libretranslate_apikey"
}

struct DamusDeepLKeychainConfiguration: KeychainConfiguration {
    var serviceName = "damus"
    var accessGroup: String? = nil
    var accountName = "deepl_apikey"
}

func pk_setting_key(_ pubkey: String, key: String) -> String {
    return "\(pubkey)_\(key)"
}

