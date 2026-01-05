//
//  SharedKeychainStorage.swift
//  damus
//
//  Created for Damoose keysigner cross-extension key access.
//

import Foundation
import Security

/// Keychain storage explicitly configured for cross-extension access.
///
/// Used by Damoose signing interfaces (Safari extension, URL scheme handler, NIP-46)
/// to read the user's keypair for signing operations.
///
/// This provides a clean, read-only API that accesses the same underlying keychain
/// storage as `Keys.privkey`, ensuring consistency with the main app's key management.
///
/// ## Usage
/// ```swift
/// guard let keypair = SharedKeychainStorage.getKeypair() else {
///     return .error("Not logged in")
/// }
/// let signed = sign(event, with: keypair)
/// ```
enum SharedKeychainStorage {

    // MARK: - Constants

    /// Service identifier matching the main app's keychain storage.
    private static let service = "damus"

    /// Account name for the private key, matching Keys.privkey storage.
    private static let privkeyAccount = "privkey"

    /// UserDefaults key for the public key, matching save_pubkey/get_saved_pubkey.
    private static let pubkeyDefaultsKey = "pubkey"

    // MARK: - Public API

    /// Retrieves the stored private key, if available.
    ///
    /// - Returns: The user's private key, or nil if not logged in or no privkey stored.
    static func getPrivateKey() -> Privkey? {
        guard let hex = readKeychainString(account: privkeyAccount) else {
            return nil
        }
        return hex_decode_privkey(hex)
    }

    /// Retrieves the stored public key, if available.
    ///
    /// - Returns: The user's public key, or nil if not logged in.
    static func getPublicKey() -> Pubkey? {
        guard let hex = DamusUserDefaults.standard.string(forKey: pubkeyDefaultsKey) else {
            return nil
        }
        guard let bytes = hex_decode(hex) else {
            return nil
        }
        return Pubkey(Data(bytes))
    }

    /// Retrieves the full keypair for signing operations.
    ///
    /// The keypair may have a nil privkey if the user logged in with only a public key
    /// (read-only mode). Callers should check `keypair.privkey != nil` before signing.
    ///
    /// - Returns: The user's keypair, or nil if not logged in.
    static func getKeypair() -> Keypair? {
        guard let pubkey = getPublicKey() else {
            return nil
        }
        let privkey = getPrivateKey()
        return Keypair(pubkey: pubkey, privkey: privkey)
    }

    /// Checks if the user has a private key available for signing.
    ///
    /// - Returns: true if a private key is stored and can be used for signing.
    static func canSign() -> Bool {
        return getPrivateKey() != nil
    }

    // MARK: - Private Helpers

    /// Reads a string value from the keychain.
    ///
    /// - Parameter account: The keychain account identifier.
    /// - Returns: The stored string value, or nil if not found.
    private static func readKeychainString(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }
        guard let data = result as? Data else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string.trimmingCharacters(in: .whitespaces)
    }
}
