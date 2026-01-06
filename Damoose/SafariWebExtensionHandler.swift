//
//  SafariWebExtensionHandler.swift
//  Damoose
//
//  Created by William Casarin on 8/5/24.
//

import SafariServices
import os.log
import Foundation
import Security
import CommonCrypto
import secp256k1

/// NIP-07 request types from the Safari extension JavaScript.
enum DamooseRequest {
    case getPublicKey
    case signEvent(SignEventPayload, remember: Bool, origin: String)
    case checkPermission(kind: Int, origin: String)
    case getRelays
    case nip04_encrypt(Nip04EncryptPayload)
    case nip04_decrypt(Nip04DecryptPayload)
}

/// Response types returned to the Safari extension JavaScript.
enum DamooseResponse {
    case pubkey(String)
    case signedEvent(SignedEvent)
    case permissionApproved

    /// The raw value to send back to JavaScript.
    var val: Any {
        switch self {
        case .pubkey(let string):
            string
        case .signedEvent(let signedEvent):
            signedEvent
        case .permissionApproved:
            ["approved": true]
        }
    }
}



/// Unsigned event payload for signing requests.
struct SignEventPayload: Codable {
    let created_at: Int
    let kind: Int
    let tags: [[String]]
    let content: String
}

/// Signed nostr event with id, signature, and pubkey.
struct SignedEvent: Codable {
    let created_at: Int
    let kind: Int
    let tags: [[String]]
    let content: String
    let id: String
    let sig: String
    let pubkey: String
}

/// Payload for NIP-04 encryption requests.
struct Nip04EncryptPayload: Codable {
    let pubkey: String
    let plaintext: String
}

/// Payload for NIP-04 decryption requests.
struct Nip04DecryptPayload: Codable {
    let pubkey: String
    let ciphertext: String
}

// MARK: - Shared Storage Constants

private let damooseAppGroupId = "group.com.damus"
private let damoosePubkeyDefaultsKey = "pubkey"
private let damooseKeychainService = "damus"
private let damoosePrivkeyAccount = "privkey"

/// Reads the stored public key from shared UserDefaults.
func getStoredPublicKey() -> String? {
    guard let defaults = UserDefaults(suiteName: damooseAppGroupId) else {
        os_log(.error, "Failed to access app group UserDefaults")
        return nil
    }
    return defaults.string(forKey: damoosePubkeyDefaultsKey)
}

/// Reads the stored private key from keychain.
func getStoredPrivateKey() -> String? {
    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: damooseKeychainService,
        kSecAttrAccount: damoosePrivkeyAccount,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
          let data = result as? Data,
          let hex = String(data: data, encoding: .utf8) else {
        return nil
    }

    return hex.trimmingCharacters(in: .whitespaces)
}

// MARK: - Permission Storage

private let damoosePermissionsKey = "damoose_permissions"

/// Builds a unique key for a permission (origin + kind).
private func permissionKey(origin: String, kind: Int) -> String {
    return "\(origin):\(kind)"
}

/// Checks if a permission has been approved for a given origin and event kind.
func isPermissionApproved(kind: Int, origin: String) -> Bool {
    guard let defaults = UserDefaults(suiteName: damooseAppGroupId) else {
        return false
    }
    let permissions = defaults.dictionary(forKey: damoosePermissionsKey) as? [String: Bool] ?? [:]
    let key = permissionKey(origin: origin, kind: kind)
    return permissions[key] == true
}

/// Saves an approved permission for a given origin and event kind.
func savePermission(kind: Int, origin: String) {
    guard let defaults = UserDefaults(suiteName: damooseAppGroupId) else {
        os_log(.error, "Failed to access app group UserDefaults for saving permission")
        return
    }
    var permissions = defaults.dictionary(forKey: damoosePermissionsKey) as? [String: Bool] ?? [:]
    let key = permissionKey(origin: origin, kind: kind)
    permissions[key] = true
    defaults.set(permissions, forKey: damoosePermissionsKey)
    os_log(.info, "Saved permission for %@ kind %d", origin, kind)
}

// MARK: - Crypto Helpers

/// Decodes a hex string to bytes.
func hexDecode(_ hex: String) -> [UInt8]? {
    guard hex.count % 2 == 0 else { return nil }
    var bytes = [UInt8]()
    var index = hex.startIndex
    while index < hex.endIndex {
        let nextIndex = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
        bytes.append(byte)
        index = nextIndex
    }
    return bytes
}

/// Encodes bytes to a hex string.
func hexEncode(_ bytes: [UInt8]) -> String {
    return bytes.map { String(format: "%02x", $0) }.joined()
}

/// Computes SHA256 hash of data.
func sha256(_ data: Data) -> Data {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return Data(hash)
}

/// Generates random bytes for schnorr signing.
func randomBytes(count: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: count)
    _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    return bytes
}

/// Computes the nostr event commitment JSON for hashing.
func eventCommitment(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    let contentJson = (try? encoder.encode(content)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    let tagsJson = (try? encoder.encode(tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    return "[0,\"\(pubkey)\",\(createdAt),\(kind),\(tagsJson),\(contentJson)]"
}

/// Computes the nostr event ID (SHA256 of commitment).
func calculateEventId(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) -> String {
    let commitment = eventCommitment(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
    guard let data = commitment.data(using: .utf8) else { return "" }
    let hash = sha256(data)
    return hexEncode(Array(hash))
}

/// Signs an event ID with the private key using schnorr signature.
func signEventId(privkeyHex: String, eventId: String) -> String? {
    guard let privkeyBytes = hexDecode(privkeyHex),
          let idBytes = hexDecode(eventId) else {
        return nil
    }

    guard let privateKey = try? secp256k1.Signing.PrivateKey(rawRepresentation: privkeyBytes) else {
        os_log(.error, "Failed to create private key from bytes")
        return nil
    }

    var auxRand = randomBytes(count: 64)
    var digest = idBytes

    guard let signature = try? privateKey.schnorr.signature(message: &digest, auxiliaryRand: &auxRand) else {
        os_log(.error, "Failed to create schnorr signature")
        return nil
    }

    return hexEncode(Array(signature.rawRepresentation))
}

// MARK: - Request Decoding

/// Decodes a message from the Safari extension JavaScript into a typed request.
///
/// - Parameter message: Raw message dictionary from the extension.
/// - Returns: Parsed request, or nil if the message is malformed.
func decode_damoose_request(_ message: Any) -> DamooseRequest? {
    guard let dict = message as? [String: Any],
          let kind = dict["kind"] as? String,
          let payloadDict = dict["payload"] as? [String: Any] else {
        os_log(.error, "Failed to decode message or invalid structure")
        return nil
    }

    switch kind {
    case "getPubKey":
        // No specific payload to decode
        return .getPublicKey

    case "signEvent":
        if let createdAt = payloadDict["created_at"] as? Int,
           let kind = payloadDict["kind"] as? Int,
           let tags = payloadDict["tags"] as? [[String]],
           let content = payloadDict["content"] as? String {
            // remember and origin come from the outer dict, not payload
            let remember = dict["remember"] as? Bool ?? false
            let origin = dict["origin"] as? String ?? ""
            return .signEvent(SignEventPayload(created_at: createdAt, kind: kind, tags: tags, content: content), remember: remember, origin: origin)
        }

    case "checkPermission":
        if let kind = payloadDict["kind"] as? Int,
           let origin = payloadDict["origin"] as? String {
            return .checkPermission(kind: kind, origin: origin)
        }

    case "getRelays":
        return .getRelays

    case "nip04Encrypt", "nip44Encrypt":
        if let pubkey = payloadDict["pubkey"] as? String,
           let plaintext = payloadDict["plaintext"] as? String {
            return .nip04_encrypt(Nip04EncryptPayload(pubkey: pubkey, plaintext: plaintext))
        }

    case "nip04Decrypt", "nip44Decrypt":
        if let pubkey = payloadDict["pubkey"] as? String,
           let ciphertext = payloadDict["ciphertext"] as? String {
            return .nip04_decrypt(Nip04DecryptPayload(pubkey: pubkey, ciphertext: ciphertext))
        }

    default:
        os_log(.error, "Unknown kind: %@", kind)
    }

    return nil
}

/// Handles a decoded request and returns the appropriate response.
///
/// - Parameter req: The decoded request.
/// - Returns: Response to send back to JavaScript, or nil if no response.
func handle_request(_ req: DamooseRequest) -> DamooseResponse? {
    switch req {
    case .getPublicKey:
        guard let pubkey = getStoredPublicKey() else {
            os_log(.error, "No pubkey stored - user not logged in")
            return nil
        }
        return .pubkey(pubkey)
    case .signEvent(let payload, let remember, let origin):
        return handleSignEvent(payload, remember: remember, origin: origin)
    case .getRelays:
        return nil
    case .nip04_encrypt(_):
        return nil
    case .nip04_decrypt(_):
        return nil
    case .checkPermission(let kind, let origin):
        let approved = isPermissionApproved(kind: kind, origin: origin)
        return approved ? .permissionApproved : nil
    }
}

// MARK: - Direct Event Signing

/// Signs an event directly using the stored private key.
///
/// This performs schnorr signing in the extension without app switching:
/// 1. Reads private key from keychain
/// 2. Computes event ID (SHA256 of commitment)
/// 3. Signs with secp256k1 schnorr
/// 4. Optionally saves permission if remember is true
/// 5. Returns complete signed event
///
/// - Parameters:
///   - payload: The unsigned event to sign.
///   - remember: If true, saves permission for this origin+kind.
///   - origin: The requesting website's origin for permission storage.
func handleSignEvent(_ payload: SignEventPayload, remember: Bool, origin: String) -> DamooseResponse? {
    guard let pubkeyHex = getStoredPublicKey() else {
        os_log(.error, "No pubkey stored - user not logged in")
        return nil
    }

    guard let privkeyHex = getStoredPrivateKey() else {
        os_log(.error, "No privkey stored - read-only mode")
        return nil
    }

    // Calculate event ID
    let eventId = calculateEventId(
        pubkey: pubkeyHex,
        createdAt: payload.created_at,
        kind: payload.kind,
        tags: payload.tags,
        content: payload.content
    )

    guard !eventId.isEmpty else {
        os_log(.error, "Failed to calculate event ID")
        return nil
    }

    // Sign the event
    guard let signature = signEventId(privkeyHex: privkeyHex, eventId: eventId) else {
        os_log(.error, "Failed to sign event")
        return nil
    }

    // Save permission if requested
    if remember && !origin.isEmpty {
        savePermission(kind: payload.kind, origin: origin)
    }

    let signedEvent = SignedEvent(
        created_at: payload.created_at,
        kind: payload.kind,
        tags: payload.tags,
        content: payload.content,
        id: eventId,
        sig: signature,
        pubkey: pubkeyHex
    )

    os_log(.info, "Signed event: %@", eventId)
    return .signedEvent(signedEvent)
}

/// Native message handler for the Damoose NIP-07 Safari extension.
///
/// Handles messages from the extension JavaScript via `browser.runtime.sendNativeMessage()`.
/// Supports getPublicKey, signEvent (delegated), and checkResult for polling.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    /// Entry point for messages from the Safari extension.
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        //os_log(.default, "Received message of kind '%@' with payload: %@", String(describing: payload))

        guard let message, let request = decode_damoose_request(message) else {
            context.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        guard let response_payload = handle_request(request) else {
            context.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: response_payload.val]
        } else {
            response.userInfo = ["message": response_payload.val]
        }

        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
