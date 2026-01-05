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

    /// Returns true if any saved account has a private key stored
    var hasAccountsWithPrivateKeys: Bool {
        accounts.contains { $0.hasPrivateKey }
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

    /// Saves a private key to the Keychain using the current storage mode.
    ///
    /// - iCloud Sync mode: Stores plaintext hex with `kSecAttrSynchronizable: true`
    /// - Local Only mode: Encrypts with Secure Enclave, stores with `kSecAttrSynchronizable: false`
    @discardableResult
    private func savePrivateKey(_ privkey: Privkey, for pubkey: Pubkey) -> Bool {
        let account = keychainAccountName(for: pubkey)
        let mode = KeyStorageSettings.mode

        // Prepare the value to store based on storage mode
        let valueToStore: Data
        let isSynchronizable: Bool

        switch mode {
        case .iCloudSync:
            // Store plaintext hex, sync to iCloud
            guard let data = privkey.hex().data(using: .utf8) else {
                Log.error("Failed to encode privkey as UTF-8", for: .storage)
                return false
            }
            valueToStore = data
            isSynchronizable = true

        case .localOnly:
            // Encrypt with Secure Enclave, no sync
            do {
                let encrypted = try SecureEnclaveStorage.encryptPrivateKey(privkey.hex())
                guard let data = encrypted.data(using: .utf8) else {
                    Log.error("Failed to encode encrypted privkey as UTF-8", for: .storage)
                    return false
                }
                valueToStore = data
                isSynchronizable = false
            } catch {
                Log.error("Failed to encrypt privkey with Secure Enclave: %@", for: .storage, String(describing: error))
                return false
            }
        }

        let query = [
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: isSynchronizable,
            kSecValueData: valueToStore as Any
        ] as [CFString: Any] as CFDictionary

        var status = SecItemAdd(query, nil)
        if status == errSecDuplicateItem {
            let searchQuery = [
                kSecAttrService: keychainService,
                kSecAttrAccount: account,
                kSecClass: kSecClassGenericPassword,
                kSecAttrSynchronizable: isSynchronizable
            ] as [CFString: Any] as CFDictionary

            let updates = [
                kSecValueData: valueToStore as Any
            ] as CFDictionary

            status = SecItemUpdate(searchQuery, updates)
        }

        if status != errSecSuccess {
            Log.error("Failed to save privkey for account, status: %d", for: .storage, Int(status))
            return false
        }

        // Only delete from the opposite mode AFTER successful save to avoid data loss
        deletePrivateKeyInMode(for: pubkey, synchronizable: !isSynchronizable)
        return true
    }

    /// Loads a private key from the Keychain.
    /// Tries to load from the current storage mode first, then falls back to the other mode and migrates.
    private func loadPrivateKey(for pubkey: Pubkey) -> Privkey? {
        let account = keychainAccountName(for: pubkey)
        let mode = KeyStorageSettings.mode

        // Try current mode first
        if let privkey = loadPrivateKeyInMode(for: pubkey, account: account, mode: mode) {
            return privkey
        }

        // Fall back to opposite mode and migrate if found
        let oppositeMode: KeyStorageMode = mode == .iCloudSync ? .localOnly : .iCloudSync
        if let privkey = loadPrivateKeyInMode(for: pubkey, account: account, mode: oppositeMode) {
            // Migrate to current mode
            Log.info("Migrating privkey from %@ to %@ mode", for: .storage, oppositeMode.rawValue, mode.rawValue)
            if savePrivateKey(privkey, for: pubkey) {
                // savePrivateKey already deletes the opposite mode key
                Log.info("Successfully migrated privkey to %@ mode", for: .storage, mode.rawValue)
            }
            return privkey
        }

        return nil
    }

    /// Loads a private key from a specific storage mode.
    private func loadPrivateKeyInMode(for pubkey: Pubkey, account: String, mode: KeyStorageMode) -> Privkey? {
        let isSynchronizable = mode == .iCloudSync

        let query = [
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: isSynchronizable,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        guard let storedString = String(data: data, encoding: .utf8) else {
            return nil
        }

        switch mode {
        case .iCloudSync:
            // Stored as plaintext hex
            return hex_decode_privkey(storedString)

        case .localOnly:
            // Stored as Secure Enclave encrypted base64
            do {
                let decryptedHex = try SecureEnclaveStorage.decryptPrivateKey(storedString)
                return hex_decode_privkey(decryptedHex)
            } catch {
                Log.error("Failed to decrypt privkey with Secure Enclave: %@", for: .storage, String(describing: error))
                // Fallback: legacy non-sync entries stored as plaintext hex (pre-multi-account).
                // Re-save to current mode - this intentionally migrates legacy keys to whatever
                // the user's current preference is (iCloud or encrypted local-only).
                guard let privkey = hex_decode_privkey(storedString) else {
                    return nil
                }
                _ = savePrivateKey(privkey, for: pubkey)
                return privkey
            }
        }
    }

    /// Deletes a private key from both storage modes.
    private func deletePrivateKey(for pubkey: Pubkey) {
        deletePrivateKeyInMode(for: pubkey, synchronizable: true)
        deletePrivateKeyInMode(for: pubkey, synchronizable: false)
    }

    /// Deletes a private key from a specific storage mode.
    private func deletePrivateKeyInMode(for pubkey: Pubkey, synchronizable: Bool) {
        let account = keychainAccountName(for: pubkey)
        let query = [
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: synchronizable
        ] as [CFString: Any] as CFDictionary
        SecItemDelete(query)
    }

    /// Migrates all stored private keys to the current storage mode.
    ///
    /// This is called when the user changes their storage mode preference (iCloud ↔ Local).
    /// Each key is loaded (which triggers auto-migration in `loadPrivateKey`), then verified
    /// to ensure it's accessible in the new mode.
    ///
    /// - Returns: A tuple of (successCount, failureCount) for migration results
    @discardableResult
    func migrateAllKeysToCurrentMode() -> (success: Int, failed: Int) {
        var successCount = 0
        var failedCount = 0
        let mode = KeyStorageSettings.mode

        for account in accounts where account.hasPrivateKey {
            // Load triggers migration if key is in opposite mode
            guard loadPrivateKey(for: account.pubkey) != nil else {
                failedCount += 1
                Log.error("Failed to load key for migration", for: .storage)
                continue
            }

            // Verify the key is now accessible in the target mode
            let verifyAccount = keychainAccountName(for: account.pubkey)
            guard loadPrivateKeyInMode(for: account.pubkey, account: verifyAccount, mode: mode) != nil else {
                failedCount += 1
                Log.error("Migration verification failed for account", for: .storage)
                continue
            }

            successCount += 1
            Log.info("Successfully migrated key for account to %@ mode", for: .storage, mode.rawValue)
        }

        // Log summary
        if failedCount > 0 {
            Log.error("Key migration completed with %d failures out of %d accounts", for: .storage, failedCount, successCount + failedCount)
        } else if successCount > 0 {
            Log.info("Key migration completed successfully for %d accounts", for: .storage, successCount)
        }

        return (successCount, failedCount)
    }
}
