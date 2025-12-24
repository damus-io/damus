//
//  KeychainStorage.swift
//  damus
//
//  Created by Bryan Montz on 5/2/23.
//

import Foundation
import Security

@propertyWrapper struct KeychainStorage {
    let account: String
    private let service = "damus"

    var wrappedValue: String? {
        get {
            let query = [
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecClass: kSecClassGenericPassword,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne
            ] as [CFString: Any] as CFDictionary

            var result: AnyObject?
            let status = SecItemCopyMatching(query, &result)

            if status == errSecSuccess, let data = result as? Data {
                return String(data: data, encoding: .utf8)
            } else {
                return nil
            }
        }
        set {
            if let newValue {
                let query = [
                    kSecAttrService: service,
                    kSecAttrAccount: account,
                    kSecClass: kSecClassGenericPassword,
                    kSecValueData: newValue.data(using: .utf8) as Any
                ] as [CFString: Any] as CFDictionary

                var status = SecItemAdd(query, nil)

                if status == errSecDuplicateItem {
                    let query = [
                        kSecAttrService: service,
                        kSecAttrAccount: account,
                        kSecClass: kSecClassGenericPassword
                    ] as [CFString: Any] as CFDictionary

                    let updates = [
                        kSecValueData: newValue.data(using: .utf8) as Any
                    ] as CFDictionary

                    status = SecItemUpdate(query, updates)
                }
            } else {
                let query = [
                    kSecAttrService: service,
                    kSecAttrAccount: account,
                    kSecClass: kSecClassGenericPassword
                ] as [CFString: Any] as CFDictionary

                _ = SecItemDelete(query)
            }
        }
    }

    init(account: String) {
        self.account = account
    }
}

/// A KeychainStorage variant that automatically scopes the account name by the current pubkey.
/// Use this for per-account secrets like wallet connections and API keys.
@propertyWrapper struct PubkeyKeychainStorage {
    let baseAccount: String
    private let service = "damus"

    /// UserDefaults key that stores the pubkey hex of the original (pre-multikey) account.
    /// Legacy keychain values are only returned for this account to prevent credential leakage.
    private static let legacyPubkeyKey = "legacy_keychain_pubkey"

    /// UserDefaults key that tracks whether legacy keypair migration completed successfully.
    /// This prevents inferring legacy ownership in scenarios where migration never happened.
    private static let legacyMigrationCompletedKey = "legacy_migration_completed"

    /// Returns the pubkey-scoped account name, falling back to base account if no pubkey is set
    private var scopedAccount: String {
        guard let pubkey = UserSettingsStore.pubkey else {
            return baseAccount
        }
        // Use first 16 chars of pubkey hex to keep keychain account name reasonable
        return "\(pubkey.hex().prefix(16))_\(baseAccount)"
    }

    /// Returns the pubkey that legacy (unscoped) keychain values belong to.
    /// This is the first account that existed before multi-account support.
    /// Must be set explicitly via setLegacyOwner() during migration - never set lazily.
    private static var legacyPubkey: Pubkey? {
        get {
            guard let hex = UserDefaults.standard.string(forKey: legacyPubkeyKey) else { return nil }
            return Pubkey(hex: hex)
        }
        set {
            if let pubkey = newValue {
                UserDefaults.standard.set(pubkey.hex(), forKey: legacyPubkeyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: legacyPubkeyKey)
            }
        }
    }

    /// Sets the legacy owner pubkey. Should be called during AccountsStore migration
    /// to ensure the correct account is granted access to legacy secrets.
    /// - Parameters:
    ///   - pubkey: The pubkey of the legacy account owner
    ///   - force: If true, overwrites any existing value. Use when the legacy keypair is present
    ///            as authoritative proof of ownership. Default false for backwards compatibility.
    static func setLegacyOwner(_ pubkey: Pubkey, force: Bool = false) {
        if force || legacyPubkey == nil {
            legacyPubkey = pubkey
        }
    }

    /// Returns whether a legacy owner has been set.
    static var hasLegacyOwner: Bool {
        legacyPubkey != nil
    }

    /// Returns whether the legacy keypair migration completed successfully.
    /// This is set during AccountsStore migration when the legacy keypair is found and migrated.
    static var legacyMigrationCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: legacyMigrationCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: legacyMigrationCompletedKey) }
    }

    /// Checks if the current pubkey is the legacy account owner.
    /// Returns false if legacy owner hasn't been set yet (prevents wrong assignment).
    private var isLegacyAccount: Bool {
        guard let currentPubkey = UserSettingsStore.pubkey else { return false }
        guard let legacy = Self.legacyPubkey else {
            // Legacy owner not set - don't grant access to prevent wrong assignment
            return false
        }
        return legacy == currentPubkey
    }

    var wrappedValue: String? {
        get {
            let account = scopedAccount
            let query = [
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecClass: kSecClassGenericPassword,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne
            ] as [CFString: Any] as CFDictionary

            var result: AnyObject?
            let status = SecItemCopyMatching(query, &result)

            if status == errSecSuccess, let data = result as? Data {
                return String(data: data, encoding: .utf8)
            } else if isLegacyAccount, let value = legacyValue {
                // Only fall back to legacy for the original account to prevent credential leakage
                // Eagerly migrate to scoped key so future reads don't need the fallback
                // Only clear legacy if scoped write succeeds to prevent data loss
                if writeToScoped(value, account: account) {
                    clearLegacyValue()
                }
                return value
            }
            return nil
        }
        set {
            let account = scopedAccount
            if let newValue {
                let query = [
                    kSecAttrService: service,
                    kSecAttrAccount: account,
                    kSecClass: kSecClassGenericPassword,
                    kSecValueData: newValue.data(using: .utf8) as Any
                ] as [CFString: Any] as CFDictionary

                var status = SecItemAdd(query, nil)

                if status == errSecDuplicateItem {
                    let searchQuery = [
                        kSecAttrService: service,
                        kSecAttrAccount: account,
                        kSecClass: kSecClassGenericPassword
                    ] as [CFString: Any] as CFDictionary

                    let updates = [
                        kSecValueData: newValue.data(using: .utf8) as Any
                    ] as CFDictionary

                    status = SecItemUpdate(searchQuery, updates)
                }

                // Clear legacy key after successful write to scoped key (only if we're the legacy owner)
                if isLegacyAccount {
                    clearLegacyValue()
                }
            } else {
                let query = [
                    kSecAttrService: service,
                    kSecAttrAccount: account,
                    kSecClass: kSecClassGenericPassword
                ] as [CFString: Any] as CFDictionary

                _ = SecItemDelete(query)
            }
        }
    }

    /// Reads from the legacy non-scoped keychain entry for migration
    private var legacyValue: String? {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    /// Clears the legacy non-scoped keychain entry after migration
    private func clearLegacyValue() {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword
        ] as [CFString: Any] as CFDictionary

        _ = SecItemDelete(query)
    }

    /// Writes a value to the specified scoped keychain account
    /// Returns true if the write succeeded, false otherwise
    @discardableResult
    private func writeToScoped(_ value: String, account: String) -> Bool {
        #if DEBUG
        // Test override for deterministic failure/success simulation
        if let override = Self.writeToScopedOverride {
            return override(value, account)
        }
        #endif

        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecValueData: value.data(using: .utf8) as Any
        ] as [CFString: Any] as CFDictionary

        var status = SecItemAdd(query, nil)

        if status == errSecDuplicateItem {
            let searchQuery = [
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecClass: kSecClassGenericPassword
            ] as [CFString: Any] as CFDictionary

            let updates = [
                kSecValueData: value.data(using: .utf8) as Any
            ] as CFDictionary

            status = SecItemUpdate(searchQuery, updates)
        }

        return status == errSecSuccess
    }

    #if DEBUG
    // MARK: - Test Hooks

    /// Test hook to override writeToScoped behavior for deterministic failure simulation.
    /// Only available in DEBUG builds.
    static var writeToScopedOverride: ((String, String) -> Bool)?
    #endif

    init(account: String) {
        self.baseAccount = account
    }
}
