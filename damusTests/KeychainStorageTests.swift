//
//  KeychainStorageTests.swift
//  damusTests
//
//  Created by Bryan Montz on 5/3/23.
//

import XCTest
@testable import damus
import Security

final class KeychainStorageTests: XCTestCase {
    @KeychainStorage(account: "test-keyname")
    var secret: String?

    override func setUp() {
        super.setUp()
        // Clean up global state that tests may modify
        UserDefaults.standard.removeObject(forKey: "legacy_migration_completed")
        UserDefaults.standard.removeObject(forKey: "legacy_keychain_pubkey")
        UserSettingsStore.pubkey = nil
        PubkeyKeychainStorage.writeToScopedOverride = nil
    }

    override func tearDown() {
        // Reset all global state
        PubkeyKeychainStorage.writeToScopedOverride = nil
        UserSettingsStore.pubkey = nil
        UserDefaults.standard.removeObject(forKey: "legacy_migration_completed")
        UserDefaults.standard.removeObject(forKey: "legacy_keychain_pubkey")
        super.tearDown()
    }

    override func tearDownWithError() throws {
        secret = nil
    }

    func testWriteToKeychain() throws {
        // write a secret to the keychain using the property wrapper's setter
        secret = "super-secure-key"

        // verify it exists in the keychain using the property wrapper's getter
        XCTAssertEqual(secret, "super-secure-key")

        // verify it exists in the keychain directly
        let query = [
            kSecAttrService: "damus",
            kSecAttrAccount: "test-keyname",
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        XCTAssertEqual(status, errSecSuccess)

        let data = try XCTUnwrap(result as? Data)
        let the_secret = String(data: data, encoding: .utf8)

        XCTAssertEqual(the_secret, "super-secure-key")
    }

    // MARK: - PubkeyKeychainStorage Legacy Migration Tests

    func testEagerMigrationPreservesLegacyValueOnRead() throws {
        // This test verifies that legacy values are accessible and returned during eager migration.
        let testPubkey = generate_new_keypair().pubkey
        let baseAccount = "test_wallet_connect_\(UUID().uuidString)"
        let legacyValue = "nostr+walletconnect://example"

        // Set up legacy owner so isLegacyAccount returns true
        PubkeyKeychainStorage.legacyMigrationCompleted = true
        PubkeyKeychainStorage.setLegacyOwner(testPubkey, force: true)

        // Set UserSettingsStore.pubkey to match (required for scoped account calculation)
        UserSettingsStore.pubkey = testPubkey

        // Insert legacy value in keychain (unscoped)
        let legacyAddQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword,
            kSecValueData: legacyValue.data(using: .utf8) as Any
        ] as [CFString: Any] as CFDictionary
        let addStatus = SecItemAdd(legacyAddQuery, nil)
        XCTAssertTrue(addStatus == errSecSuccess || addStatus == errSecDuplicateItem,
                      "Failed to add legacy keychain entry: \(addStatus)")

        // Access via PubkeyKeychainStorage - this should trigger eager migration
        @PubkeyKeychainStorage(account: baseAccount) var value: String?
        let readValue = value

        // Verify we got the legacy value back
        XCTAssertEqual(readValue, legacyValue)

        // Verify legacy entry was cleared after successful migration
        var result: AnyObject?
        let legacyReadQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any] as CFDictionary
        let status = SecItemCopyMatching(legacyReadQuery, &result)
        XCTAssertEqual(status, errSecItemNotFound, "Legacy entry should be cleared after successful migration")

        // Verify scoped entry now exists
        let scopedAccount = "\(testPubkey.hex().prefix(16))_\(baseAccount)"
        let scopedReadQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: scopedAccount,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any] as CFDictionary
        var scopedResult: AnyObject?
        let scopedStatus = SecItemCopyMatching(scopedReadQuery, &scopedResult)
        XCTAssertEqual(scopedStatus, errSecSuccess, "Scoped entry should exist after migration")

        if let data = scopedResult as? Data, let scopedValue = String(data: data, encoding: .utf8) {
            XCTAssertEqual(scopedValue, legacyValue)
        } else {
            XCTFail("Could not read scoped value")
        }

        // Clean up keychain entries using minimal delete queries
        let legacyDeleteQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword
        ] as [CFString: Any] as CFDictionary
        SecItemDelete(legacyDeleteQuery)

        let scopedDeleteQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: scopedAccount,
            kSecClass: kSecClassGenericPassword
        ] as [CFString: Any] as CFDictionary
        SecItemDelete(scopedDeleteQuery)
    }

    func testNonLegacyAccountCannotAccessLegacySecrets() throws {
        // Verify that accounts other than the legacy owner cannot access legacy secrets
        let legacyPubkey = generate_new_keypair().pubkey
        let otherPubkey = generate_new_keypair().pubkey
        let baseAccount = "test_wallet_secret_\(UUID().uuidString)"
        let legacyValue = "nostr+walletconnect://secret"

        // Set up legacy owner
        PubkeyKeychainStorage.legacyMigrationCompleted = true
        PubkeyKeychainStorage.setLegacyOwner(legacyPubkey, force: true)

        // Insert legacy value
        let legacyAddQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword,
            kSecValueData: legacyValue.data(using: .utf8) as Any
        ] as [CFString: Any] as CFDictionary
        SecItemAdd(legacyAddQuery, nil)

        // Set current user to a DIFFERENT pubkey
        UserSettingsStore.pubkey = otherPubkey

        // Try to access - should NOT get the legacy value
        @PubkeyKeychainStorage(account: baseAccount) var value: String?
        let readValue = value

        XCTAssertNil(readValue, "Non-legacy account should not be able to access legacy secrets")

        // Legacy entry should still exist (not migrated for wrong account)
        var result: AnyObject?
        let legacyReadQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any] as CFDictionary
        let status = SecItemCopyMatching(legacyReadQuery, &result)
        XCTAssertEqual(status, errSecSuccess, "Legacy entry should still exist")

        // Clean up keychain entry using minimal delete query
        let legacyDeleteQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword
        ] as [CFString: Any] as CFDictionary
        SecItemDelete(legacyDeleteQuery)
    }

    func testEagerMigrationKeepsLegacyOnScopedWriteFailure() throws {
        // Verify that legacy entry is preserved when scoped write fails
        let legacyPubkey = generate_new_keypair().pubkey
        let baseAccount = "test_wallet_connect_\(UUID().uuidString)"
        let legacyValue = "nostr+walletconnect://example"

        PubkeyKeychainStorage.legacyMigrationCompleted = true
        PubkeyKeychainStorage.setLegacyOwner(legacyPubkey, force: true)
        UserSettingsStore.pubkey = legacyPubkey

        // Force scoped write failure via test hook
        PubkeyKeychainStorage.writeToScopedOverride = { _, _ in false }

        // Insert legacy entry
        let legacyAddQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword,
            kSecValueData: legacyValue.data(using: .utf8) as Any
        ] as [CFString: Any] as CFDictionary
        SecItemAdd(legacyAddQuery, nil)

        // Access via PubkeyKeychainStorage - scoped write will fail
        @PubkeyKeychainStorage(account: baseAccount) var value: String?
        XCTAssertEqual(value, legacyValue, "Should still return legacy value even when scoped write fails")

        // Legacy entry should still exist (write failed, so no deletion)
        var result: AnyObject?
        let readQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any] as CFDictionary
        let status = SecItemCopyMatching(readQuery, &result)
        XCTAssertEqual(status, errSecSuccess, "Legacy entry should still exist when scoped write fails")

        // Clean up keychain entry
        let deleteQuery = [
            kSecAttrService: "damus",
            kSecAttrAccount: baseAccount,
            kSecClass: kSecClassGenericPassword
        ] as [CFString: Any] as CFDictionary
        SecItemDelete(deleteQuery)
    }
}
