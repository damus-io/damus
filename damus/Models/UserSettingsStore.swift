//
//  UserSettingsStore.swift
//  damus
//
//  Created by Suhail Saqan on 12/29/22.
//

import Foundation
import UIKit

let fallback_zap_amount = 1000

func setting_property_key(key: String) -> String {
    return pk_setting_key(UserSettingsStore.pubkey ?? .empty, key: key)
}

func setting_get_property_value<T>(key: String, scoped_key: String, default_value: T) -> T {
    if let loaded = UserDefaults.standard.object(forKey: scoped_key) as? T {
        return loaded
    } else if let loaded = UserDefaults.standard.object(forKey: key) as? T {
        // If pubkey-scoped setting does not exist but the deprecated non-pubkey-scoped setting does,
        // migrate the deprecated setting into the pubkey-scoped one and delete the deprecated one.
        UserDefaults.standard.set(loaded, forKey: scoped_key)
        UserDefaults.standard.removeObject(forKey: key)
        return loaded
    } else {
        return default_value
    }
}

func setting_set_property_value<T: Equatable>(scoped_key: String, old_value: T, new_value: T) -> T? {
    guard old_value != new_value else { return nil }
    UserDefaults.standard.set(new_value, forKey: scoped_key)
    UserSettingsStore.shared?.objectWillChange.send()
    return new_value
}

@propertyWrapper struct Setting<T: Equatable> {
    private let key: String
    private var value: T
    
    init(key: String, default_value: T) {
        if T.self == Bool.self {
            UserSettingsStore.bool_options.insert(key)
        }
        let scoped_key = setting_property_key(key: key)

        self.value = setting_get_property_value(key: key, scoped_key: scoped_key, default_value: default_value)
        self.key = scoped_key
    }

    var wrappedValue: T {
        get { return value }
        set {
            guard let new_val = setting_set_property_value(scoped_key: key, old_value: value, new_value: newValue) else { return }
            self.value = new_val
        }
    }
}

@propertyWrapper class StringSetting<T: StringCodable & Equatable> {
    private let key: String
    private var value: T
    
    init(key: String, default_value: T) {
        self.key = pk_setting_key(UserSettingsStore.pubkey ?? .empty, key: key)
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
    static var pubkey: Pubkey? = nil
    static var shared: UserSettingsStore? = nil
    static var bool_options = Set<String>()
    
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
    
    @Setting(key: "hide_nsfw_tagged_content", default_value: false)
    var hide_nsfw_tagged_content: Bool

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

    @Setting(key: "font_size", default_value: 1.0)
    var font_size: Double

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

    @Setting(key: "show_general_statuses", default_value: true)
    var show_general_statuses: Bool

    @Setting(key: "show_music_statuses", default_value: true)
    var show_music_statuses: Bool

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
    
    @Setting(key: "developer_mode", default_value: false)
    var developer_mode: Bool
    
    @Setting(key: "emoji_reactions", default_value: default_emoji_reactions)
    var emoji_reactions: [String]
    
    @Setting(key: "default_emoji_reaction", default_value: "🤙")
    var default_emoji_reaction: String

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

    @StringSetting(key: "libretranslate_server", default_value: .custom)
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

func pk_setting_key(_ pubkey: Pubkey, key: String) -> String {
    return "\(pubkey.hex())_\(key)"
}
