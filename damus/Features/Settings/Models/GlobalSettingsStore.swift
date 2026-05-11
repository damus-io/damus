//
//  GlobalSettingsStore.swift
//  damus
//
//  Created for device-level settings that apply globally across all accounts
//

import Foundation
import Combine

/// A property wrapper for global (non-pubkey-scoped) settings.
/// Use this for device-level preferences that should apply regardless of which account is logged in.
@propertyWrapper struct GlobalSetting<T: Equatable> {
    private let key: String
    private var value: T
    
    init(key: String, default_value: T) {
        if T.self == Bool.self {
            GlobalSettingsStore.bool_options.insert(key)
        }
        self.key = key
        self.value = DamusUserDefaults.standard.object(forKey: key) as? T ?? default_value
    }

    var wrappedValue: T {
        get { return value }
        set {
            guard value != newValue else { return }
            self.value = newValue
            DamusUserDefaults.standard.set(newValue, forKey: key)
            DispatchQueue.main.async {
                GlobalSettingsStore.shared.objectWillChange.send()
            }
        }
    }
}

/// Store for global (device-level) settings that apply regardless of which account is logged in.
///
/// Unlike `UserSettingsStore`, these settings are not scoped to a specific pubkey.
/// Use this for device preferences like privacy settings, accessibility options, etc.
class GlobalSettingsStore: ObservableObject {
    static let shared = GlobalSettingsStore()
    static var bool_options = Set<String>()
    
    private init() {}
    
    /// Controls whether Sentry telemetry and error reporting is enabled.
    /// When disabled, no data is sent to Sentry for crash reporting or diagnostics.
    /// This is a global setting that applies to all accounts on this device.
    @GlobalSetting(key: "enable_sentry_telemetry", default_value: false)
    var enable_sentry_telemetry: Bool
}
