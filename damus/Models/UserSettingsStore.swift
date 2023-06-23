//
//  UserSettingsStore.swift
//  damus
//
//  Created by Suhail Saqan on 12/29/22.
//

import Foundation
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
            // If pubkey-scoped setting does not exist but the deprecated non-pubkey-scoped setting does,
            // migrate the deprecated setting into the pubkey-scoped one and delete the deprecated one.
            self.value = loaded
            UserDefaults.standard.set(loaded, forKey: self.key)
            UserDefaults.standard.removeObject(forKey: key)
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
            // If pubkey-scoped setting does not exist but the deprecated non-pubkey-scoped setting does,
            // migrate the deprecated setting into the pubkey-scoped one and delete the deprecated one.
            self.value = val
            UserDefaults.standard.set(val.to_string(), forKey: self.key)
            UserDefaults.standard.removeObject(forKey: key)
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
    
    @Setting(key: "show_wallet_selector", default_value: false)
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
    
    @StringSetting(key: "zap_type", default_value: ZapType.pub)
    var default_zap_type: ZapType

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
    
    /// Nozaps mode gimps note zapping to fit into apple's content-tipping guidelines. It can not be configurable to end-users on the app store
    @Setting(key: "nozaps", default_value: true)
    var nozaps: Bool
    
    @Setting(key: "truncate_mention_text", default_value: true)
    var truncate_mention_text: Bool
    
    @Setting(key: "notification_indicators", default_value: NewEventsBits.all.rawValue)
    var notification_indicators: Int
    
    @Setting(key: "auto_translate", default_value: true)
    var auto_translate: Bool

    @Setting(key: "show_only_preferred_languages", default_value: false)
    var show_only_preferred_languages: Bool
    
    @Setting(key: "multiple_events_per_pubkey", default_value: false)
    var multiple_events_per_pubkey: Bool

    @Setting(key: "onlyzaps_mode", default_value: false)
    var onlyzaps_mode: Bool
    
    @Setting(key: "disable_animation", default_value: UIAccessibility.isReduceMotionEnabled)
    var disable_animation: Bool
    
    @Setting(key: "donation_percent", default_value: 0)
    var donation_percent: Int

    // Helper for inverse of disable_animation.
    // disable_animation was introduced as a setting first, but it's more natural for the settings UI to show the inverse.
    var enable_animation: Bool {
        get {
            !disable_animation
        }
        set {
            disable_animation = !newValue
        }
    }
    
    @StringSetting(key: "friend_filter", default_value: .all)
    var friend_filter: FriendFilter

    @StringSetting(key: "translation_service", default_value: .none)
    var translation_service: TranslationService

    @StringSetting(key: "deepl_plan", default_value: .free)
    var deepl_plan: DeepLPlan
    
    var deepl_api_key: String {
        get {
            return internal_deepl_api_key ?? ""
        }
        set {
            internal_deepl_api_key = newValue == "" ? nil : newValue
        }
    }

    @StringSetting(key: "libretranslate_server", default_value: .terraprint)
    var libretranslate_server: LibreTranslateServer
    
    @Setting(key: "libretranslate_url", default_value: "")
    var libretranslate_url: String

    var libretranslate_api_key: String {
        get {
            return internal_libretranslate_api_key ?? ""
        }
        set {
            internal_libretranslate_api_key = newValue == "" ? nil : newValue
        }
    }
    
    var nokyctranslate_api_key: String {
        get {
            return internal_nokyctranslate_api_key ?? ""
        }
        set {
            internal_nokyctranslate_api_key = newValue == "" ? nil : newValue
        }
    }
    
    // These internal keys are necessary because entries in the keychain need to be Optional,
    // but the translation view needs non-Optional String in order to use them as Bindings.
    @KeychainStorage(account: "deepl_apikey")
    var internal_deepl_api_key: String?
    
    @KeychainStorage(account: "nokyctranslate_apikey")
    var internal_nokyctranslate_api_key: String?
    
    @KeychainStorage(account: "libretranslate_apikey")
    var internal_libretranslate_api_key: String?
    
    @KeychainStorage(account: "nostr_wallet_connect")
    var nostr_wallet_connect: String? // TODO: strongly type this to WalletConnectURL

    var can_translate: Bool {
        switch translation_service {
        case .none:
            return false
        case .libretranslate:
            return URLComponents(string: libretranslate_url) != nil
        case .deepl:
            return internal_deepl_api_key != nil
        case .nokyctranslate:
            return internal_nokyctranslate_api_key != nil
        }
    }
}

func pk_setting_key(_ pubkey: String, key: String) -> String {
    return "\(pubkey)_\(key)"
}
