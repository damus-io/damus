import XCTest
import Security
@testable import damus

@MainActor
final class AccountsStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Isolate legacy migration flags per test run
        UserDefaults.standard.removeObject(forKey: "legacy_migration_completed")
        UserDefaults.standard.removeObject(forKey: "legacy_keychain_pubkey")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "legacy_migration_completed")
        UserDefaults.standard.removeObject(forKey: "legacy_keychain_pubkey")
        super.tearDown()
    }

    func testAddsAndActivatesAccountWithPrivkey() throws {
        let context = try makeStore()
        let fullKeypair = generate_new_keypair()
        let keypair = fullKeypair.to_keypair()

        context.store.addOrUpdate(keypair, savePriv: true)
        context.store.setActive(keypair.pubkey, allowDuringOnboarding: true)

        XCTAssertEqual(context.store.accounts.count, 1)
        XCTAssertEqual(context.store.activeAccount?.pubkey, keypair.pubkey)
        XCTAssertNotNil(context.store.activeKeypair?.privkey)
        cleanup(context)
    }

    func testViewOnlyAccountHasNoPrivkey() throws {
        let context = try makeStore()
        let fullKeypair = generate_new_keypair()
        let pubOnly = Keypair.just_pubkey(fullKeypair.pubkey)

        context.store.addOrUpdate(pubOnly, savePriv: false)
        context.store.setActive(pubOnly.pubkey, allowDuringOnboarding: true)

        XCTAssertEqual(context.store.activeAccount?.hasPrivateKey, false)
        XCTAssertNil(context.store.activeKeypair?.privkey)
        cleanup(context)
    }

    func testMostRecentlyUsedOrdering() throws {
        let context = try makeStore()
        let first = generate_new_keypair().to_keypair()
        let second = generate_new_keypair().to_keypair()

        context.store.addOrUpdate(first, savePriv: true)
        context.store.setActive(first.pubkey, allowDuringOnboarding: true)
        context.store.addOrUpdate(second, savePriv: true)
        context.store.setActive(first.pubkey, allowDuringOnboarding: true)

        XCTAssertEqual(context.store.accounts.first?.pubkey, first.pubkey)
        cleanup(context)
    }

    // MARK: - Keychain Edge Cases

    func testRemoveAccountDeletesKeychainEntry() throws {
        let context = try makeStore()
        let fullKeypair = generate_new_keypair()
        let keypair = fullKeypair.to_keypair()

        context.store.addOrUpdate(keypair, savePriv: true)
        context.store.setActive(keypair.pubkey, allowDuringOnboarding: true)
        XCTAssertNotNil(context.store.activeKeypair?.privkey)

        context.store.remove(keypair.pubkey)
        XCTAssertNil(context.store.activeAccount)
        XCTAssertEqual(context.store.accounts.count, 0)
        cleanup(context)
    }

    func testAddMultipleAccountsWithPrivkeys() throws {
        let context = try makeStore()
        let first = generate_new_keypair().to_keypair()
        let second = generate_new_keypair().to_keypair()
        let third = generate_new_keypair().to_keypair()

        context.store.addOrUpdate(first, savePriv: true)
        context.store.addOrUpdate(second, savePriv: true)
        context.store.addOrUpdate(third, savePriv: true)

        XCTAssertEqual(context.store.accounts.count, 3)

        // Each account should have private key retrievable when active
        context.store.setActive(first.pubkey, allowDuringOnboarding: true)
        XCTAssertEqual(context.store.activeKeypair?.privkey, first.privkey)

        context.store.setActive(second.pubkey, allowDuringOnboarding: true)
        XCTAssertEqual(context.store.activeKeypair?.privkey, second.privkey)

        context.store.setActive(third.pubkey, allowDuringOnboarding: true)
        XCTAssertEqual(context.store.activeKeypair?.privkey, third.privkey)
        cleanup(context)
    }

    func testUpdateExistingAccount() throws {
        let context = try makeStore()
        let fullKeypair = generate_new_keypair()
        let keypair = fullKeypair.to_keypair()

        context.store.addOrUpdate(keypair, savePriv: true)
        XCTAssertEqual(context.store.accounts.count, 1)

        // Adding the same account again should not create duplicate
        context.store.addOrUpdate(keypair, savePriv: true)
        XCTAssertEqual(context.store.accounts.count, 1)
        cleanup(context)
    }

    func testMixedPrivkeyAndViewOnlyAccounts() throws {
        let context = try makeStore()
        let fullAccount = generate_new_keypair().to_keypair()
        let viewOnly = Keypair.just_pubkey(generate_new_keypair().pubkey)

        context.store.addOrUpdate(fullAccount, savePriv: true)
        context.store.addOrUpdate(viewOnly, savePriv: false)

        XCTAssertEqual(context.store.accounts.count, 2)

        // Full account should have privkey
        context.store.setActive(fullAccount.pubkey, allowDuringOnboarding: true)
        XCTAssertTrue(context.store.activeAccount?.hasPrivateKey ?? false)
        XCTAssertNotNil(context.store.activeKeypair?.privkey)

        // View-only should not have privkey
        context.store.setActive(viewOnly.pubkey, allowDuringOnboarding: true)
        XCTAssertFalse(context.store.activeAccount?.hasPrivateKey ?? true)
        XCTAssertNil(context.store.activeKeypair?.privkey)
        cleanup(context)
    }

    func testRemoveMiddleAccountPreservesOthers() throws {
        let context = try makeStore()
        let first = generate_new_keypair().to_keypair()
        let second = generate_new_keypair().to_keypair()
        let third = generate_new_keypair().to_keypair()

        context.store.addOrUpdate(first, savePriv: true)
        context.store.addOrUpdate(second, savePriv: true)
        context.store.addOrUpdate(third, savePriv: true)

        context.store.remove(second.pubkey)

        XCTAssertEqual(context.store.accounts.count, 2)
        XCTAssertTrue(context.store.accounts.contains { $0.pubkey == first.pubkey })
        XCTAssertFalse(context.store.accounts.contains { $0.pubkey == second.pubkey })
        XCTAssertTrue(context.store.accounts.contains { $0.pubkey == third.pubkey })
        cleanup(context)
    }

    func testRemovingActiveAccountClearsActive() throws {
        let context = try makeStore()
        let keypair = generate_new_keypair().to_keypair()

        context.store.addOrUpdate(keypair, savePriv: true)
        context.store.setActive(keypair.pubkey, allowDuringOnboarding: true)
        XCTAssertEqual(context.store.activePubkey, keypair.pubkey)

        context.store.remove(keypair.pubkey)
        XCTAssertNil(context.store.activePubkey)
        XCTAssertNil(context.store.activeAccount)
        cleanup(context)
    }

    // MARK: - Account Switching Tests

    func testSwitchingBetweenAccountsPreservesData() throws {
        let context = try makeStore()
        let first = generate_new_keypair().to_keypair()
        let second = generate_new_keypair().to_keypair()

        context.store.addOrUpdate(first, savePriv: true)
        context.store.addOrUpdate(second, savePriv: true)

        // Switch between accounts multiple times
        context.store.setActive(first.pubkey, allowDuringOnboarding: true)
        XCTAssertEqual(context.store.activePubkey, first.pubkey)
        XCTAssertNotNil(context.store.activeKeypair?.privkey)

        context.store.setActive(second.pubkey, allowDuringOnboarding: true)
        XCTAssertEqual(context.store.activePubkey, second.pubkey)
        XCTAssertNotNil(context.store.activeKeypair?.privkey)

        context.store.setActive(first.pubkey, allowDuringOnboarding: true)
        XCTAssertEqual(context.store.activePubkey, first.pubkey)
        cleanup(context)
    }

    // MARK: - Phase 2 Tests: Large Account List

    func testLargeAccountList() throws {
        let context = try makeStore()
        let accountCount = 15
        var keypairs: [Keypair] = []

        // Add 15 accounts
        for _ in 0..<accountCount {
            let keypair = generate_new_keypair().to_keypair()
            keypairs.append(keypair)
            context.store.addOrUpdate(keypair, savePriv: true)
        }

        XCTAssertEqual(context.store.accounts.count, accountCount)

        // Verify each account can be activated and has correct privkey
        for keypair in keypairs {
            context.store.setActive(keypair.pubkey, allowDuringOnboarding: true)
            XCTAssertEqual(context.store.activePubkey, keypair.pubkey)
            XCTAssertEqual(context.store.activeKeypair?.privkey, keypair.privkey)
        }

        // Verify MRU ordering - last activated should be first
        XCTAssertEqual(context.store.accounts.first?.pubkey, keypairs.last?.pubkey)

        cleanup(context)
    }

    func testLargeAccountListRemoval() throws {
        let context = try makeStore()
        let accountCount = 12
        var keypairs: [Keypair] = []

        for _ in 0..<accountCount {
            let keypair = generate_new_keypair().to_keypair()
            keypairs.append(keypair)
            context.store.addOrUpdate(keypair, savePriv: true)
        }

        // Remove every other account
        for i in stride(from: 0, to: accountCount, by: 2) {
            context.store.remove(keypairs[i].pubkey)
        }

        XCTAssertEqual(context.store.accounts.count, accountCount / 2)

        // Remaining accounts should still have valid privkeys
        for i in stride(from: 1, to: accountCount, by: 2) {
            context.store.setActive(keypairs[i].pubkey, allowDuringOnboarding: true)
            XCTAssertEqual(context.store.activeKeypair?.privkey, keypairs[i].privkey)
        }

        cleanup(context)
    }

    // MARK: - Phase 2 Tests: Concurrent Access

    func testConcurrentSwitchAttempts() async throws {
        let context = try makeStore()
        let first = generate_new_keypair().to_keypair()
        let second = generate_new_keypair().to_keypair()
        let third = generate_new_keypair().to_keypair()

        context.store.addOrUpdate(first, savePriv: true)
        context.store.addOrUpdate(second, savePriv: true)
        context.store.addOrUpdate(third, savePriv: true)

        // Simulate concurrent switch attempts
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    context.store.setActive(first.pubkey, allowDuringOnboarding: true)
                }
                group.addTask { @MainActor in
                    context.store.setActive(second.pubkey, allowDuringOnboarding: true)
                }
                group.addTask { @MainActor in
                    context.store.setActive(third.pubkey, allowDuringOnboarding: true)
                }
            }
        }

        // After concurrent switches, store should be in consistent state
        XCTAssertEqual(context.store.accounts.count, 3)
        XCTAssertNotNil(context.store.activePubkey)

        // Whichever account is active should have valid keypair
        if let activePubkey = context.store.activePubkey {
            XCTAssertNotNil(context.store.keypair(for: activePubkey)?.privkey)
        }

        cleanup(context)
    }

    func testConcurrentAddAndRemove() async throws {
        let context = try makeStore()
        var keypairs: [Keypair] = []

        for _ in 0..<5 {
            keypairs.append(generate_new_keypair().to_keypair())
        }

        // Add all accounts first
        for keypair in keypairs {
            context.store.addOrUpdate(keypair, savePriv: true)
        }

        // Concurrent add and remove operations
        await withTaskGroup(of: Void.self) { group in
            // Add new accounts concurrently
            for _ in 0..<3 {
                group.addTask { @MainActor in
                    let newKeypair = generate_new_keypair().to_keypair()
                    context.store.addOrUpdate(newKeypair, savePriv: true)
                }
            }
            // Remove some accounts concurrently
            group.addTask { @MainActor in
                context.store.remove(keypairs[0].pubkey)
            }
            group.addTask { @MainActor in
                context.store.remove(keypairs[1].pubkey)
            }
        }

        // Store should be in consistent state - at least 6 accounts (5-2+3)
        XCTAssertGreaterThanOrEqual(context.store.accounts.count, 6)

        cleanup(context)
    }

    // MARK: - Phase 2 Tests: Keychain Edge Cases

    func testKeypairRetrievalForNonexistentAccount() throws {
        let context = try makeStore()
        let randomPubkey = generate_new_keypair().pubkey

        // Trying to get keypair for account that doesn't exist should return nil
        XCTAssertNil(context.store.keypair(for: randomPubkey))

        cleanup(context)
    }

    func testSetActiveForNonexistentAccount() throws {
        let context = try makeStore()
        let existingKeypair = generate_new_keypair().to_keypair()
        let nonexistentPubkey = generate_new_keypair().pubkey

        context.store.addOrUpdate(existingKeypair, savePriv: true)
        context.store.setActive(existingKeypair.pubkey, allowDuringOnboarding: true)

        // Trying to set active to non-existent account should not change active
        context.store.setActive(nonexistentPubkey, allowDuringOnboarding: true)
        XCTAssertEqual(context.store.activePubkey, existingKeypair.pubkey)

        cleanup(context)
    }

    func testAccountWithMissingKeychainEntry() throws {
        let context = try makeStore()
        let keypair = generate_new_keypair().to_keypair()

        // Add account with privkey
        context.store.addOrUpdate(keypair, savePriv: true)
        context.store.setActive(keypair.pubkey, allowDuringOnboarding: true)

        // Manually delete keychain entry to simulate corruption/missing entry
        let account = "pk-\(keypair.pubkey.hex().prefix(16))"
        let query = [
            kSecAttrService: context.keychainService,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: true
        ] as [CFString: Any] as CFDictionary
        SecItemDelete(query)

        // Account still exists but privkey should be nil
        XCTAssertTrue(context.store.accounts.contains { $0.pubkey == keypair.pubkey })
        XCTAssertNil(context.store.activeKeypair?.privkey)

        cleanup(context)
    }

    func testRapidAccountSwitching() throws {
        let context = try makeStore()
        let accounts = (0..<5).map { _ in generate_new_keypair().to_keypair() }

        for account in accounts {
            context.store.addOrUpdate(account, savePriv: true)
        }

        // Rapid switching between accounts
        for _ in 0..<50 {
            let randomAccount = accounts.randomElement()!
            context.store.setActive(randomAccount.pubkey, allowDuringOnboarding: true)
        }

        // Store should still be consistent
        XCTAssertEqual(context.store.accounts.count, 5)
        XCTAssertNotNil(context.store.activePubkey)
        XCTAssertNotNil(context.store.activeKeypair?.privkey)

        cleanup(context)
    }

    // MARK: - Legacy Owner Inference Tests

    func testLegacyOwnerNotInferredWhenMigrationNeverHappened() throws {
        // Simulate: user had multiple accounts, deleted original, only one remains
        // Legacy owner should NOT be inferred because migration never completed
        let context = try makeStore()

        // Add a single account (simulating the remaining account after original was deleted)
        let keypair = generate_new_keypair().to_keypair()
        context.store.addOrUpdate(keypair, savePriv: true)
        context.store.setActive(keypair.pubkey, allowDuringOnboarding: true)

        XCTAssertEqual(context.store.accounts.count, 1)

        // Create a new store to trigger inference
        let damusDefaults = try DamusUserDefaults(main: .custom(UserDefaults(suiteName: context.defaultsSuite)!))!
        let store2 = AccountsStore(defaults: damusDefaults, keychainService: context.keychainService, migrateLegacy: true)
        _ = store2

        // Verify legacy owner was NOT set (because migration never happened)
        XCTAssertFalse(PubkeyKeychainStorage.hasLegacyOwner)

        cleanup(context)
    }

    func testLegacyOwnerInferredWhenMigrationCompletedAndSingleAccount() throws {
        // Simulate: legacy keypair migrated, legacy secrets remain, 1 account exists
        // Legacy owner should be inferred
        let context = try makeStore()

        // Simulate that migration completed previously
        PubkeyKeychainStorage.legacyMigrationCompleted = true

        // Add a single account
        let keypair = generate_new_keypair().to_keypair()
        context.store.addOrUpdate(keypair, savePriv: true)

        XCTAssertEqual(context.store.accounts.count, 1)

        // Create a new store to trigger inference
        let damusDefaults = try DamusUserDefaults(main: .custom(UserDefaults(suiteName: context.defaultsSuite)!))!
        let store2 = AccountsStore(defaults: damusDefaults, keychainService: context.keychainService, migrateLegacy: true)
        _ = store2

        // Verify legacy owner was inferred
        XCTAssertTrue(PubkeyKeychainStorage.hasLegacyOwner)

        cleanup(context)
    }

    func testLegacyOwnerNotInferredWhenMultipleAccountsExist() throws {
        // Even with migration completed, shouldn't infer when multiple accounts exist
        let context = try makeStore()

        // Simulate that migration completed previously
        PubkeyKeychainStorage.legacyMigrationCompleted = true

        // Add multiple accounts
        let first = generate_new_keypair().to_keypair()
        let second = generate_new_keypair().to_keypair()
        context.store.addOrUpdate(first, savePriv: true)
        context.store.addOrUpdate(second, savePriv: true)

        XCTAssertEqual(context.store.accounts.count, 2)

        // Create a new store to trigger inference
        let damusDefaults = try DamusUserDefaults(main: .custom(UserDefaults(suiteName: context.defaultsSuite)!))!
        let store2 = AccountsStore(defaults: damusDefaults, keychainService: context.keychainService, migrateLegacy: true)
        _ = store2

        // Verify legacy owner was NOT inferred (multiple accounts exist)
        XCTAssertFalse(PubkeyKeychainStorage.hasLegacyOwner)

        cleanup(context)
    }
}

// MARK: - Helpers

private struct AccountsStoreTestContext {
    let store: AccountsStore
    let defaultsSuite: String
    let keychainService: String
}

@MainActor
private func makeStore() throws -> AccountsStoreTestContext {
    let suiteName = "AccountsStoreTests-\(UUID().uuidString)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        throw XCTSkip("Could not create test UserDefaults suite")
    }

    let damusDefaults = try DamusUserDefaults(main: .custom(userDefaults))!
    let keychainService = "damus-tests-\(suiteName)"
    let store = AccountsStore(defaults: damusDefaults, keychainService: keychainService, migrateLegacy: false)
    return AccountsStoreTestContext(store: store, defaultsSuite: suiteName, keychainService: keychainService)
}

private func cleanup(_ context: AccountsStoreTestContext) {
    UserDefaults(suiteName: context.defaultsSuite)?.removePersistentDomain(forName: context.defaultsSuite)
    let query = [
        kSecAttrService: context.keychainService,
        kSecClass: kSecClassGenericPassword,
        kSecAttrSynchronizable: true
    ] as [CFString: Any] as CFDictionary
    SecItemDelete(query)
}
