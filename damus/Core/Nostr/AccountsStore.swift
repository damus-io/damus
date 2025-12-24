//
//  AccountsStore.swift
//  damus
//
//  Created by AI Assistant on 2025-07-30.
//

import Foundation
import Security

struct SavedAccount: Codable, Identifiable, Equatable {
    let pubkey: Pubkey
    var displayName: String?
    var avatarURL: URL?
    let hasPrivateKey: Bool
    let addedAt: Date

    var id: String {
        pubkey.hex()
    }
}

/// Persists multiple accounts and the active selection.
/// - Stores pubkeys/metadata in `DamusUserDefaults`.
/// - Stores privkeys per account in the Keychain under a short, stable account name.
@MainActor
final class AccountsStore: ObservableObject {
    static let shared = AccountsStore()

    @Published private(set) var accounts: [SavedAccount] = []
    @Published private(set) var activePubkey: Pubkey?

    /// Transient keypair for "Login without saving" - not persisted, cleared on logout
    private var transientKeypair: Keypair?

    /// Flag to prevent onChange(activePubkey) from racing with .onReceive(.login)
    /// Set before activePubkey changes in setActiveTransient, cleared by login handler
    @Published private(set) var isSettingTransientSession = false

    private let defaults: DamusUserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let accountsKey = "accounts_v1"
    private let activeKey = "active_pubkey_v1"
    private let keychainService: String

    init(defaults: DamusUserDefaults = .standard, keychainService: String = "damus", migrateLegacy: Bool = true) {
        self.defaults = defaults
        self.keychainService = keychainService
        loadFromDisk()
        if migrateLegacy {
            // Read legacy keypair once and pass to both functions to avoid duplicate Keychain I/O
            let legacyKeypair = get_saved_keypair()
            migrateLegacyKeypairIfNeeded(legacyKeypair: legacyKeypair)
            inferLegacyOwnerIfNeeded(legacyKeypairExists: legacyKeypair != nil)
        }
    }

    /// Infers the legacy owner when the legacy keypair was already cleared but legacy secrets may remain.
    /// This handles the case where a user upgraded, the keypair migrated successfully, but legacy
    /// keychain entries (e.g., wallet connections) remain from before the migration.
    ///
    /// - Parameter legacyKeypairExists: Whether a legacy keypair was found (passed from init to avoid duplicate Keychain read)
    private func inferLegacyOwnerIfNeeded(legacyKeypairExists: Bool) {
        // Only infer if legacy owner hasn't been set yet
        guard !PubkeyKeychainStorage.hasLegacyOwner else { return }

        // If there's exactly one account, it must be the original legacy account
        // This is safe because multi-account support didn't exist before this migration
        guard accounts.count == 1, let onlyAccount = accounts.first else { return }

        // Check if migration happened (with flag) OR migration happened before the flag existed.
        // The latter case is detected when: no legacy keypair exists AND no migration flag is set
        // AND there's exactly one account - this combination indicates old migration cleared the keypair.
        let migrationHappened = PubkeyKeychainStorage.legacyMigrationCompleted
        let preFlagMigration = !migrationHappened && !legacyKeypairExists && accounts.count == 1

        guard migrationHappened || preFlagMigration else { return }

        PubkeyKeychainStorage.setLegacyOwner(onlyAccount.pubkey)
        if preFlagMigration {
            Log.info("Inferred legacy owner from single existing account (pre-flag migration)", for: .storage)
        } else {
            Log.info("Inferred legacy owner from single existing account", for: .storage)
        }
    }

    var activeAccount: SavedAccount? {
        guard let activePubkey else { return nil }
        return accounts.first { $0.pubkey == activePubkey }
    }

    var activeKeypair: Keypair? {
        // Check transient keypair first (for "Login without saving")
        if let transient = transientKeypair, transient.pubkey == activePubkey {
            return transient
        }
        guard let activePubkey else { return nil }
        return keypair(for: activePubkey)
    }

    func setActive(_ pubkey: Pubkey, allowDuringOnboarding: Bool = false) {
        if OnboardingSession.shared.isOnboarding && !allowDuringOnboarding {
            return
        }
        guard accounts.contains(where: { $0.pubkey == pubkey }) else { return }
        transientKeypair = nil  // Clear any transient session when switching to saved account
        activePubkey = pubkey
        defaults.set(pubkey.hex(), forKey: activeKey)
        moveToFront(pubkey: pubkey)
        persistAccounts()
    }

    /// Sets a transient active session for "Login without saving".
    /// The keypair is kept in memory only and not persisted.
    func setActiveTransient(_ keypair: Keypair) {
        // Set flag BEFORE activePubkey to prevent onChange from racing with onReceive(.login)
        isSettingTransientSession = true
        transientKeypair = keypair
        activePubkey = keypair.pubkey
        // Don't persist to UserDefaults - this is session-only
        // Flag is cleared by the login notification handler in MainView
    }

    /// Clears the transient session flag. Called by login handler after taking over.
    func clearTransientSessionFlag() {
        isSettingTransientSession = false
    }

    func addOrUpdate(_ keypair: Keypair, savePriv: Bool) {
        _ = addOrUpdateReturningSuccess(keypair, savePriv: savePriv)
    }

    /// Adds or updates an account, returning whether the operation succeeded.
    /// Returns false only if savePriv was true and the keychain write failed.
    @discardableResult
    private func addOrUpdateReturningSuccess(_ keypair: Keypair, savePriv: Bool) -> Bool {
        let pubkey = keypair.pubkey
        let existing = accounts.first(where: { $0.pubkey == pubkey })

        var keychainSucceeded = true
        if savePriv, let privkey = keypair.privkey {
            keychainSucceeded = savePrivateKey(privkey, for: pubkey)
        }

        // Only mark hasPrivateKey if we actually saved it successfully
        let hasPriv = (savePriv && keypair.privkey != nil && keychainSucceeded) || (existing?.hasPrivateKey ?? false)
        let account = SavedAccount(
            pubkey: pubkey,
            displayName: existing?.displayName,
            avatarURL: existing?.avatarURL,
            hasPrivateKey: hasPriv,
            addedAt: existing?.addedAt ?? Date()
        )

        accounts.removeAll { $0.pubkey == pubkey }
        accounts.insert(account, at: 0) // MRU
        persistAccounts()

        return keychainSucceeded
    }

    func remove(_ pubkey: Pubkey) {
        accounts.removeAll { $0.pubkey == pubkey }
        deletePrivateKey(for: pubkey)
        persistAccounts()

        guard let activePubkey, activePubkey == pubkey else { return }
        clearActive()
    }

    func clearActiveSelection() {
        clearActive()
    }

    /// Updates the display name and avatar URL for a saved account
    func updateMetadata(for pubkey: Pubkey, displayName: String?, avatarURL: URL?) {
        guard let index = accounts.firstIndex(where: { $0.pubkey == pubkey }) else { return }
        let existing = accounts[index]

        // Only update if there's actually new data
        let newDisplayName = displayName ?? existing.displayName
        let newAvatarURL = avatarURL ?? existing.avatarURL

        guard newDisplayName != existing.displayName || newAvatarURL != existing.avatarURL else { return }

        let updated = SavedAccount(
            pubkey: existing.pubkey,
            displayName: newDisplayName,
            avatarURL: newAvatarURL,
            hasPrivateKey: existing.hasPrivateKey,
            addedAt: existing.addedAt
        )
        accounts[index] = updated
        persistAccounts()
    }

    func keypair(for pubkey: Pubkey) -> Keypair? {
        guard accounts.contains(where: { $0.pubkey == pubkey }) else { return nil }
        let privkey = loadPrivateKey(for: pubkey)
        return Keypair(pubkey: pubkey, privkey: privkey)
    }

    private func moveToFront(pubkey: Pubkey) {
        guard let index = accounts.firstIndex(where: { $0.pubkey == pubkey }) else { return }
        guard index != 0 else { return }
        let account = accounts.remove(at: index)
        accounts.insert(account, at: 0)
    }

    private func persistAccounts() {
        guard let data = try? encoder.encode(accounts) else { return }
        defaults.set(data, forKey: accountsKey)
    }

    private func loadFromDisk() {
        if let data = defaults.object(forKey: accountsKey) as? Data,
           let decoded = try? decoder.decode([SavedAccount].self, from: data) {
            accounts = decoded
        }

        guard let activeHex = defaults.string(forKey: activeKey),
              let active = Pubkey(hex: activeHex),
              accounts.contains(where: { $0.pubkey == active }) else {
            return
        }

        activePubkey = active
    }

    private func clearActive() {
        transientKeypair = nil  // Clear any transient session
        isSettingTransientSession = false  // Clear flag in case of abandoned login
        activePubkey = nil
        defaults.removeObject(forKey: activeKey)
    }

    private func migrateLegacyKeypairIfNeeded(legacyKeypair: Keypair?) {
        // Check if we have a legacy keypair that needs migration
        guard let legacyKeypair else { return }

        // The presence of a legacy keypair is authoritative proof of the original account.
        // Always set/correct the legacy owner for PubkeyKeychainStorage migration.
        // This fixes any incorrect assignment from previous versions.
        PubkeyKeychainStorage.setLegacyOwner(legacyKeypair.pubkey, force: true)

        // Check if we already have this account (possibly from a failed previous migration)
        let existingAccount = accounts.first { $0.pubkey == legacyKeypair.pubkey }

        // If account exists with privkey flag set, migration previously succeeded.
        // But verify keychain entry actually exists (could be missing after device restore/keychain reset).
        if existingAccount?.hasPrivateKey == true {
            if loadPrivateKey(for: legacyKeypair.pubkey) != nil {
                // Keychain entry exists - safe to clean up legacy
                markMigrationCompleted()
                try? clear_keypair()
                return
            } else if let privkey = legacyKeypair.privkey {
                // Keychain entry missing but we have legacy privkey - re-save it
                Log.info("Keychain entry missing for migrated account, re-saving from legacy", for: .storage)
                if savePrivateKey(privkey, for: legacyKeypair.pubkey) {
                    // Update account record to ensure hasPrivateKey is consistent
                    // Preserve existing position (this is internal recovery, not user-initiated switch)
                    if let existing = existingAccount,
                       let existingIndex = accounts.firstIndex(where: { $0.pubkey == existing.pubkey }) {
                        let updated = SavedAccount(
                            pubkey: existing.pubkey,
                            displayName: existing.displayName,
                            avatarURL: existing.avatarURL,
                            hasPrivateKey: true,
                            addedAt: existing.addedAt
                        )
                        accounts[existingIndex] = updated
                        persistAccounts()
                    }
                    markMigrationCompleted()
                    try? clear_keypair()
                }
                // If re-save failed, keep legacy keypair for next retry
                return
            }
            // No privkey in legacy either - nothing to recover, just clean up
            markMigrationCompleted()
            try? clear_keypair()
            return
        }

        // If account exists without privkey, a previous migration failed - retry keychain save
        // If no account exists, this is a fresh migration
        let needsPrivkeySave = legacyKeypair.privkey != nil

        if needsPrivkeySave {
            let keychainSucceeded = savePrivateKey(legacyKeypair.privkey!, for: legacyKeypair.pubkey)
            if !keychainSucceeded {
                // Keychain write failed - don't persist account, don't clear legacy, allow retry on next launch
                Log.error("Migration failed: could not save privkey to new keychain location, will retry on next launch", for: .storage)
                return
            }
        }

        // Keychain save succeeded (or wasn't needed) - now safe to persist account and clear legacy
        let account = SavedAccount(
            pubkey: legacyKeypair.pubkey,
            displayName: existingAccount?.displayName,
            avatarURL: existingAccount?.avatarURL,
            hasPrivateKey: needsPrivkeySave,
            addedAt: existingAccount?.addedAt ?? Date()
        )

        accounts.removeAll { $0.pubkey == legacyKeypair.pubkey }
        accounts.insert(account, at: 0)
        persistAccounts()

        setActive(legacyKeypair.pubkey, allowDuringOnboarding: true)

        markMigrationCompleted()
        try? clear_keypair()
    }

    /// Marks that legacy keypair migration completed successfully.
    /// This flag is used to determine if legacy owner can be inferred for secret access.
    private func markMigrationCompleted() {
        PubkeyKeychainStorage.legacyMigrationCompleted = true
    }

    private func keychainAccountName(for pubkey: Pubkey) -> String {
        "pk-\(pubkey.hex().prefix(16))"
    }

    /// Saves a private key to the Keychain with iCloud sync enabled.
    ///
    /// Note: `kSecAttrSynchronizable: true` enables iCloud Keychain sync, allowing
    /// private keys to sync across the user's devices. This is a convenience feature
    /// but represents a security/privacy tradeoff that should be documented in release notes.
    @discardableResult
    private func savePrivateKey(_ privkey: Privkey, for pubkey: Pubkey) -> Bool {
        let account = keychainAccountName(for: pubkey)
        let query = [
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: true,
            kSecValueData: privkey.hex().data(using: .utf8) as Any
        ] as [CFString: Any] as CFDictionary

        var status = SecItemAdd(query, nil)
        if status == errSecDuplicateItem {
            let searchQuery = [
                kSecAttrService: keychainService,
                kSecAttrAccount: account,
                kSecClass: kSecClassGenericPassword,
                kSecAttrSynchronizable: true
            ] as [CFString: Any] as CFDictionary

            let updates = [
                kSecValueData: privkey.hex().data(using: .utf8) as Any
            ] as CFDictionary

            status = SecItemUpdate(searchQuery, updates)
        }

        if status != errSecSuccess {
            Log.error("Failed to save privkey for account, status: %d", for: .storage, Int(status))
            return false
        }
        return true
    }

    private func loadPrivateKey(for pubkey: Pubkey) -> Privkey? {
        let account = keychainAccountName(for: pubkey)

        // First try to load synchronizable key (new format)
        let syncQuery = [
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any] as CFDictionary

        var result: AnyObject?
        var status = SecItemCopyMatching(syncQuery, &result)

        // If not found, try non-synchronizable key (legacy format) and migrate it
        if status == errSecItemNotFound {
            let legacyQuery = [
                kSecAttrService: keychainService,
                kSecAttrAccount: account,
                kSecClass: kSecClassGenericPassword,
                kSecAttrSynchronizable: false,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne
            ] as [CFString: Any] as CFDictionary

            status = SecItemCopyMatching(legacyQuery, &result)

            // If found legacy key, migrate it to synchronizable
            if status == errSecSuccess, let data = result as? Data,
               let hexString = String(data: data, encoding: .utf8),
               let privkey = hex_decode_privkey(hexString) {
                // Re-save as synchronizable and delete legacy
                if savePrivateKey(privkey, for: pubkey) {
                    let deleteQuery = [
                        kSecAttrService: keychainService,
                        kSecAttrAccount: account,
                        kSecClass: kSecClassGenericPassword,
                        kSecAttrSynchronizable: false
                    ] as [CFString: Any] as CFDictionary
                    SecItemDelete(deleteQuery)
                }
                return privkey
            }
        }

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        guard let hexString = String(data: data, encoding: .utf8),
              let privkey = hex_decode_privkey(hexString) else {
            return nil
        }

        return privkey
    }

    private func deletePrivateKey(for pubkey: Pubkey) {
        let account = keychainAccountName(for: pubkey)

        // Delete synchronizable key (new format)
        let syncQuery = [
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: true
        ] as [CFString: Any] as CFDictionary
        SecItemDelete(syncQuery)

        // Also delete legacy non-synchronizable key if it exists
        let legacyQuery = [
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: false
        ] as [CFString: Any] as CFDictionary
        SecItemDelete(legacyQuery)
    }
}
