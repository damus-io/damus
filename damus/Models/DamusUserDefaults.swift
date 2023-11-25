//
//  DamusUserDefaults.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-25.
//

import Foundation

/// DamusUserDefaults
/// This struct acts like a drop-in replacement for `UserDefaults.standard`
/// for cases where we want to store such items in a UserDefaults that is shared among the Damus app group
/// so that they can be accessed from other target (e.g. The notification extension target).
///
/// This struct handles migration automatically to the new shared UserDefaults
struct DamusUserDefaults {
    static let shared: DamusUserDefaults = DamusUserDefaults()
    private static let default_suite_name: String = "group.com.damus"  // Shared defaults for this app group
    
    private let suite_name: String
    private let defaults: UserDefaults
    
    // MARK: - Initializers
    
    init() {
        self.init(suite_name: Self.default_suite_name)! // Pretty low risk to force-unwrap given that the default suite name is a constant.
    }
    
    init?(suite_name: String = Self.default_suite_name) {
        self.suite_name = suite_name
        guard let defaults = UserDefaults(suiteName: suite_name) else {
            return nil
        }
        self.defaults = defaults
    }
    
    // MARK: - Functions for feature parity with UserDefaults.standard
    
    func string(forKey defaultName: String) -> String? {
        if let value = self.defaults.string(forKey: defaultName) {
            return value
        }
        let fallback_value = UserDefaults.standard.string(forKey: defaultName)
        self.defaults.set(fallback_value, forKey: defaultName)  // Migrate
        return fallback_value
    }
    
    func set(_ value: Any?, forKey defaultName: String) {
        self.defaults.set(value, forKey: defaultName)
    }
    
    func removeObject(forKey defaultName: String) {
        self.defaults.removeObject(forKey: defaultName)
        // Remove from standard UserDefaults to avoid it coming back as a fallback_value when we fetch it next time
        UserDefaults.standard.removeObject(forKey: defaultName)
    }
    
    func object(forKey defaultName: String) -> Any? {
        if let value = self.defaults.object(forKey: defaultName) {
            return value
        }
        let fallback_value = UserDefaults.standard.string(forKey: defaultName)
        self.defaults.set(fallback_value, forKey: defaultName)  // Migrate
        return fallback_value
    }
    
}
