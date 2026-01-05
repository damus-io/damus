//
//  UserSettingsStore.swift
//  damus
//
//  Created by Suhail Saqan on 12/29/22.
//

import Foundation
import UIKit

let fallback_zap_amount = 21
let default_emoji_reactions = ["🤣", "🤙", "⚡", "💜", "🔥", "😀", "😃", "😄", "🥶"]

func setting_property_key(key: String) -> String {
    return pk_setting_key(UserSettingsStore.pubkey ?? .empty, key: key)
}

func setting_get_property_value<T>(key: String, scoped_key: String, default_value: T) -> T {
    if let loaded = DamusUserDefaults.standard.object(forKey: scoped_key) as? T {
        return loaded
    } else if let loaded = DamusUserDefaults.standard.object(forKey: key) as? T {
        // If pubkey-scoped setting does not exist but the deprecated non-pubkey-scoped setting does,
        // migrate the deprecated setting into the pubkey-scoped one and delete the deprecated one.
        DamusUserDefaults.standard.set(loaded, forKey: scoped_key)
        DamusUserDefaults.standard.removeObject(forKey: key)
        return loaded
    } else {
        return default_value
    }
}

func setting_set_property_value<T: Equatable>(scoped_key: String, old_value: T, new_value: T) -> T? {
    guard old_value != new_value else { return nil }
    DamusUserDefaults.standard.set(new_value, forKey: scoped_key)
    DispatchQueue.main.async {
        UserSettingsStore.shared?.objectWillChange.send()
    }
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
        if let loaded = DamusUserDefaults.standard.string(forKey: self.key), let val = T.init(from: loaded) {
            self.value = val
        } else if let loaded = DamusUserDefaults.standard.string(forKey: key), let val = T.init(from: loaded) {
            // If pubkey-scoped setting does not exist but the deprecated non-pubkey-scoped setting does,
            // migrate the deprecated setting into the pubkey-scoped one and delete the deprecated one.
            self.value = val
            DamusUserDefaults.standard.set(val.to_string(), forKey: self.key)
            DamusUserDefaults.standard.removeObject(forKey: key)
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
            DamusUserDefaults.standard.set(newValue.to_string(), forKey: key)
            UserSettingsStore.shared!.objectWillChange.send()
        }
    }
}

class UserSettingsStore: ObservableObject {
    static var pubkey: Pubkey? = nil
    static var shared: UserSettingsStore? = nil
    static var bool_options = Set<String>()
    
    static func globally_load_for(pubkey: Pubkey) -> UserSettingsStore {
        // dumb stuff needed for property wrappers
        UserSettingsStore.pubkey = pubkey
        let settings = UserSettingsStore()
        UserSettingsStore.shared = settings
        return settings
    }
    
    @StringSetting(key: "default_wallet", default_value: .system_default_wallet)
    var default_wallet: Wallet
    
    @StringSetting(key: "default_media_uploader", default_value: .nostrBuild)
    var default_media_uploader: MediaUploader
    
    @Setting(key: "show_wallet_selector", default_value: false)
    var show_wallet_selector: Bool
    
    @Setting(key: "dismiss_wallet_high_balance_warning", default_value: false)
    var dismiss_wallet_high_balance_warning: Bool

    @Setting(key: "hide_wallet_balance", default_value: false)
    var hide_wallet_balance: Bool

    @Setting(key: "left_handed", default_value: false)
    var left_handed: Bool
    
    @Setting(key: "blur_images", default_value: true)
    var blur_images: Bool
    
    @Setting(key: "media_previews", default_value: true)
    var media_previews: Bool

    @Setting(key: "show_trusted_replies_first", default_value: true)
    var show_trusted_replies_first: Bool

    @Setting(key: "reset_tips_on_launch", default_value: false)
    var reset_tips_on_launch: Bool

    @Setting(key: "hide_nsfw_tagged_content", default_value: false)
    var hide_nsfw_tagged_content: Bool
    
    @Setting(key: "reduce_bitcoin_content", default_value: false)
    var reduce_bitcoin_content: Bool
    
    @Setting(key: "show_profile_action_sheet_on_pfp_click", default_value: true)
    var show_profile_action_sheet_on_pfp_click: Bool

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

    @Setting(key: "longform_sepia_mode", default_value: false)
    var longform_sepia_mode: Bool

    @Setting(key: "longform_line_height", default_value: 1.5)
    var longform_line_height: Double

    @Setting(key: "dm_notification", default_value: true)
    var dm_notification: Bool
    
    @Setting(key: "like_notification", default_value: true)
    var like_notification: Bool
    
    @StringSetting(key: "notification_mode", default_value: .push)
    var notification_mode: NotificationsMode
    
    @Setting(key: "notification_only_from_following", default_value: false)
    var notification_only_from_following: Bool

    @Setting(key: "hellthread_notifications_disabled", default_value: false)
    var hellthread_notifications_disabled: Bool

    @Setting(key: "hellthread_notification_max_pubkeys", default_value: DEFAULT_HELLTHREAD_MAX_PUBKEYS)
    var hellthread_notification_max_pubkeys: Int

    @Setting(key: "translate_dms", default_value: false)
    var translate_dms: Bool
    
    @Setting(key: "truncate_timeline_text", default_value: false)
    var truncate_timeline_text: Bool
    
    /// Nozaps mode gimps note zapping to fit into apple's content-tipping guidelines. It can not be configurable to end-users on the app store
    ///
    /// Update 2025-05-12: This can be re-enabled 🥳. See https://github.com/damus-io/damus/issues/3016
    // @Setting(key: "nozaps", default_value: true)
    var nozaps: Bool {
        return false
    }
    
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
    
    /// Makes all post content gibberish and blurhashes images, to avoid distractions when developers are working.
    @Setting(key: "undistract_mode", default_value: false)
    var undistractMode: Bool
    
    @Setting(key: "always_show_onboarding_suggestions", default_value: false)
    var always_show_onboarding_suggestions: Bool

    // @Setting(key: "enable_experimental_push_notifications", default_value: false)
    // This was a feature flag setting during early development, but now this is enabled for everyone.
    var enable_push_notifications: Bool = true
    
    @StringSetting(key: "push_notification_environment", default_value: .production)
    var push_notification_environment: PushNotificationClient.Environment
    
    @Setting(key: "enable_experimental_purple_api", default_value: false)
    var enable_experimental_purple_api: Bool
    
    /// Whether the app has the experimental local relay model flag that streams data only from the local relay (ndb)
    @Setting(key: "enable_experimental_local_relay_model", default_value: false)
    var enable_experimental_local_relay_model: Bool
    
    /// Whether the app should present the experimental floating "Load new content" button
    @Setting(key: "enable_experimental_load_new_content_button", default_value: false)
    var enable_experimental_load_new_content_button: Bool
    
    @StringSetting(key: "purple_environment", default_value: .production)
    var purple_enviroment: DamusPurpleEnvironment

    @Setting(key: "enable_experimental_purple_iap_support", default_value: false)
    var enable_experimental_purple_iap_support: Bool
    
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

    var winetranslate_api_key: String {
        get {
            return internal_winetranslate_api_key ?? ""
        }
        set {
            internal_winetranslate_api_key = newValue == "" ? nil : newValue
        }
    }
    
    // These internal keys are necessary because entries in the keychain need to be Optional,
    // but the translation view needs non-Optional String in order to use them as Bindings.
    @KeychainStorage(account: "deepl_apikey")
    var internal_deepl_api_key: String?
    
    @KeychainStorage(account: "nokyctranslate_apikey")
    var internal_nokyctranslate_api_key: String?

    @KeychainStorage(account: "winetranslate_apikey")
    var internal_winetranslate_api_key: String?
    
    @KeychainStorage(account: "libretranslate_apikey")
    var internal_libretranslate_api_key: String?
    
    @KeychainStorage(account: "nostr_wallet_connect")
    var nostr_wallet_connect: String? // TODO: strongly type this to WalletConnectURL

    var can_translate: Bool {
        switch translation_service {
        case .none:
            return false
        case .purple:
            return true
        case .libretranslate:
            return URLComponents(string: libretranslate_url) != nil
        case .deepl:
            return internal_deepl_api_key != nil
        case .nokyctranslate:
            return internal_nokyctranslate_api_key != nil
        case .winetranslate:
            return internal_winetranslate_api_key != nil
        }
    }
    
    // MARK: Damus Labs Experiments
    @Setting(key: "live", default_value: false)
    var live: Bool
    
    /// Whether the app should show the Favourites feature (Damus Labs)
    @Setting(key: "labs_experiment_favorites", default_value: false)
    var enable_favourites_feature: Bool
    
    // MARK: Internal, hidden settings
    
    // TODO: Get rid of this once we have NostrDB query capabilities integrated
    @Setting(key: "latest_contact_event_id", default_value: nil)
    var latest_contact_event_id_hex: String?
    
    // TODO: Get rid of this once we have NostrDB query capabilities integrated
    @Setting(key: "draft_event_ids", default_value: nil)
    var draft_event_ids: [String]?
    
    // TODO: Get rid of this once we have NostrDB query capabilities integrated
    @Setting(key: "latest_relay_list_event_id", default_value: nil)
    var latestRelayListEventIdHex: String?
    
    // MARK: Helper types
    
    enum NotificationsMode: String, CaseIterable, Identifiable, StringCodable, Equatable {
        var id: String { self.rawValue }

        func to_string() -> String {
            return rawValue
        }
        
        init?(from string: String) {
            guard let notifications_mode = NotificationsMode(rawValue: string) else {
                return nil
            }
            self = notifications_mode
        }
        
        func text_description() -> String {
            switch self {
                case .local:
                    NSLocalizedString("Local", comment: "Option for notification mode setting: Local notification mode")
                case .push:
                    NSLocalizedString("Push", comment: "Option for notification mode setting: Push notification mode")
            }
        }
        
        case local
        case push
    }
    
}

func pk_setting_key(_ pubkey: Pubkey, key: String) -> String {
    return "\(pubkey.hex())_\(key)"
}
