//
//  SecureEnclaveStorage.swift
//  damus
//
//  Created for multi-account key storage security.
//

import Foundation
import Security
import LocalAuthentication

/// Provides Secure Enclave-based encryption for private keys.
///
/// The Secure Enclave generates a hardware-bound EC key pair that never leaves the device.
/// We use this to encrypt nostr private keys before storing them in the Keychain.
/// This provides protection even if the Keychain is compromised.
///
/// Note: Secure Enclave keys are deleted when the app is uninstalled.
enum SecureEnclaveStorage {

    /// Tag used to identify our Secure Enclave key in the Keychain
    private static let keyTag = "io.damus.secure-enclave-key".data(using: .utf8)!

    /// Errors that can occur during Secure Enclave operations
    enum SecureEnclaveError: Error, LocalizedError {
        case notAvailable
        case keyGenerationFailed(OSStatus)
        case keyNotFound
        case encryptionFailed(Error)
        case decryptionFailed(Error)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Secure Enclave is not available on this device"
            case .keyGenerationFailed(let status):
                return "Failed to generate Secure Enclave key: \(status)"
            case .keyNotFound:
                return "Secure Enclave key not found"
            case .encryptionFailed(let error):
                return "Encryption failed: \(error.localizedDescription)"
            case .decryptionFailed(let error):
                return "Decryption failed: \(error.localizedDescription)"
            case .invalidData:
                return "Invalid data format"
            }
        }
    }

    /// Checks if Secure Enclave is available on this device.
    ///
    /// This performs an actual key creation attempt with kSecAttrTokenIDSecureEnclave,
    /// which is the only reliable way to detect SE availability. The test key is
    /// immediately deleted after the check.
    static var isAvailable: Bool {
        // Use a unique tag for the availability test key
        let testTag = "io.damus.secure-enclave-availability-test".data(using: .utf8)!

        // Create access control for SE key
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            nil
        ) else {
            return false
        }

        // Attempt to create an actual Secure Enclave key
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: testTag,
                kSecAttrAccessControl: accessControl
            ] as [CFString: Any]
        ]

        var error: Unmanaged<CFError>?
        guard let testKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            // Key creation failed - Secure Enclave not available
            return false
        }

        // SE is available - clean up the test key
        _ = testKey  // Silence unused variable warning
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: testTag,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        return true
    }

    /// Gets or creates the Secure Enclave key pair.
    /// The private key never leaves the Secure Enclave; we get a reference to use for operations.
    private static func getOrCreateKey() throws -> SecKey {
        // Try to find existing key first
        if let existingKey = try? getExistingKey() {
            return existingKey
        }

        // Create new key if none exists
        return try createKey()
    }

    /// Retrieves an existing Secure Enclave key
    private static func getExistingKey() throws -> SecKey {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: keyTag,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecReturnRef: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let key = result else {
            throw SecureEnclaveError.keyNotFound
        }

        return key as! SecKey
    }

    /// Creates a new Secure Enclave key pair
    private static func createKey() throws -> SecKey {
        guard isAvailable else {
            throw SecureEnclaveError.notAvailable
        }

        // Create access control - key can only be used when device is unlocked
        // and stays on this device only (no iCloud sync)
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            nil
        ) else {
            throw SecureEnclaveError.keyGenerationFailed(errSecParam)
        }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: keyTag,
                kSecAttrAccessControl: accessControl
            ] as [CFString: Any]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let err = error?.takeRetainedValue() {
                Log.error("Secure Enclave key generation failed: %@", for: .storage, String(describing: err))
            }
            throw SecureEnclaveError.keyGenerationFailed(errSecParam)
        }

        return privateKey
    }

    /// Encrypts data using the Secure Enclave public key.
    /// The encrypted data can only be decrypted on this device using the Secure Enclave.
    ///
    /// - Parameter data: The data to encrypt (e.g., a private key hex string as Data)
    /// - Returns: The encrypted data
    static func encrypt(_ data: Data) throws -> Data {
        let privateKey = try getOrCreateKey()

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecureEnclaveError.encryptionFailed(SecureEnclaveError.keyNotFound)
        }

        // Use ECIES encryption which is appropriate for EC keys
        let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA256AESGCM

        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            throw SecureEnclaveError.encryptionFailed(SecureEnclaveError.notAvailable)
        }

        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(publicKey, algorithm, data as CFData, &error) else {
            if let err = error?.takeRetainedValue() {
                throw SecureEnclaveError.encryptionFailed(err)
            }
            throw SecureEnclaveError.encryptionFailed(SecureEnclaveError.invalidData)
        }

        return encryptedData as Data
    }

    /// Decrypts data using the Secure Enclave private key.
    /// This operation requires the Secure Enclave hardware.
    ///
    /// - Parameter encryptedData: The data previously encrypted with `encrypt(_:)`
    /// - Returns: The original decrypted data
    static func decrypt(_ encryptedData: Data) throws -> Data {
        let privateKey = try getOrCreateKey()

        let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA256AESGCM

        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
            throw SecureEnclaveError.decryptionFailed(SecureEnclaveError.notAvailable)
        }

        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(privateKey, algorithm, encryptedData as CFData, &error) else {
            if let err = error?.takeRetainedValue() {
                throw SecureEnclaveError.decryptionFailed(err)
            }
            throw SecureEnclaveError.decryptionFailed(SecureEnclaveError.invalidData)
        }

        return decryptedData as Data
    }

    /// Encrypts a private key hex string for secure storage.
    ///
    /// - Parameter privkeyHex: The private key as a hex string
    /// - Returns: Base64-encoded encrypted data suitable for Keychain storage
    static func encryptPrivateKey(_ privkeyHex: String) throws -> String {
        guard let data = privkeyHex.data(using: .utf8) else {
            throw SecureEnclaveError.invalidData
        }

        let encrypted = try encrypt(data)
        return encrypted.base64EncodedString()
    }

    /// Decrypts a previously encrypted private key.
    ///
    /// - Parameter encryptedBase64: The Base64-encoded encrypted data from `encryptPrivateKey(_:)`
    /// - Returns: The original private key hex string
    static func decryptPrivateKey(_ encryptedBase64: String) throws -> String {
        guard let encryptedData = Data(base64Encoded: encryptedBase64) else {
            throw SecureEnclaveError.invalidData
        }

        let decrypted = try decrypt(encryptedData)

        guard let privkeyHex = String(data: decrypted, encoding: .utf8) else {
            throw SecureEnclaveError.invalidData
        }

        return privkeyHex
    }

    /// Deletes the Secure Enclave key.
    /// Warning: This will make all encrypted private keys unrecoverable!
    static func deleteKey() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: keyTag,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave
        ]

        SecItemDelete(query as CFDictionary)
    }
}
