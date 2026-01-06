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

enum DamooseRequest {
    case getPublicKey
    case signEvent(SignEventPayload)
    case checkResult(String)  // requestId
    case getRelays
    case nip04_encrypt(Nip04EncryptPayload)
    case nip04_decrypt(Nip04DecryptPayload)
}

enum DamooseResponse {
    case pubkey(String)
    case signedEvent(SignedEvent)

    var val: Any {
        switch self {
        case .pubkey(let string):
            string
        case .signedEvent(let signedEvent):
            signedEvent
        }
    }
}



struct SignEventPayload: Codable {
    let created_at: Int
    let kind: Int
    let tags: [[String]]
    let content: String
}

struct SignedEvent: Codable {
    let created_at: Int
    let kind: Int
    let tags: [[String]]
    let content: String
    let id: String
    let sig: String
    let pubkey: String
}

struct Nip04EncryptPayload: Codable {
    let pubkey: String
    let plaintext: String
}

struct Nip04DecryptPayload: Codable {
    let pubkey: String
    let ciphertext: String
}

// You can define similar structs for nip44 encryption/decryption if needed.

// MARK: - Shared Keychain Storage

private let damooseAppGroupId = "group.com.damus"
private let damooseKeychainService = "damus"
private let damoosePrivkeyAccount = "privkey"
private let damoosePubkeyDefaultsKey = "pubkey"

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

// MARK: - Request Decoding

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
            return .signEvent(SignEventPayload(created_at: createdAt, kind: kind, tags: tags, content: content))
        }

    case "getRelays":
        return .getRelays

    case "checkResult":
        if let requestId = payloadDict["requestId"] as? String {
            return .checkResult(requestId)
        }

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

func handle_request(_ req: DamooseRequest) -> DamooseResponse? {
    switch req {
    case .getPublicKey:
        guard let pubkey = getStoredPublicKey() else {
            os_log(.error, "No pubkey stored - user not logged in")
            return nil
        }
        return .pubkey(pubkey)
    case .signEvent(let payload):
        return handleSignEvent(payload)
    case .checkResult(let requestId):
        return getSignResult(requestId: requestId)
    case .getRelays:
        return nil
    case .nip04_encrypt(_):
        return nil
    case .nip04_decrypt(_):
        return nil
    }
}

// MARK: - Sign Event Delegation

/// Uses the same storage key pattern as SignerBridgeStorage for consistency.
private let signerRequestPrefix = "signer_request_"
private let signerResultPrefix = "signer_result_"

/// Stores a signing request and returns a response indicating the request needs app processing.
///
/// The flow for signEvent:
/// 1. This handler stores the request in App Group UserDefaults
/// 2. Returns a special response with requestId and nostrsigner URL
/// 3. JS side opens the URL (switches to Damus app)
/// 4. Damus app signs and stores result
/// 5. JS polls via checkResult to get the signed event
func handleSignEvent(_ payload: SignEventPayload) -> DamooseResponse? {
    guard let defaults = UserDefaults(suiteName: damooseAppGroupId) else {
        os_log(.error, "Failed to access app group for signing request")
        return nil
    }

    // Convert payload to JSON for storage
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes

    let eventDict: [String: Any] = [
        "created_at": payload.created_at,
        "kind": payload.kind,
        "tags": payload.tags,
        "content": payload.content
    ]

    guard let eventData = try? JSONSerialization.data(withJSONObject: eventDict),
          let eventJson = String(data: eventData, encoding: .utf8) else {
        os_log(.error, "Failed to serialize event payload")
        return nil
    }

    // Generate request ID
    let requestId = UUID().uuidString

    // Store the request (matching SignerBridgeStorage format)
    let request: [String: Any] = [
        "event": eventJson,
        "origin": "safari-extension",
        "timestamp": Date().timeIntervalSince1970
    ]

    defaults.set(request, forKey: signerRequestPrefix + requestId)
    defaults.synchronize()

    os_log(.info, "Stored sign request: %@", requestId)

    // Build nostrsigner:// URL that the JS side can open
    guard let encodedEvent = eventJson.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
        return nil
    }

    // The URL triggers the Damus app, which will process and store result
    let signerUrl = "nostrsigner:\(encodedEvent)?type=sign_event&extensionRequestId=\(requestId)&returnType=event"

    // Return nil for now - the native handler can't return arbitrary data
    // The extension JS flow needs to be updated to open the URL and poll
    // For now, log the URL for debugging
    os_log(.info, "Sign URL: %@", signerUrl)

    return nil
}

/// Retrieves a signing result from shared storage.
/// Called when polling for results after the main app has signed.
func getSignResult(requestId: String) -> DamooseResponse? {
    guard let defaults = UserDefaults(suiteName: damooseAppGroupId),
          let result = defaults.dictionary(forKey: signerResultPrefix + requestId) else {
        return nil
    }

    // Clean up
    defaults.removeObject(forKey: signerResultPrefix + requestId)
    defaults.removeObject(forKey: signerRequestPrefix + requestId)
    defaults.synchronize()

    // Check for error
    if let _ = result["error"] as? String {
        return nil
    }

    // Parse the signed event JSON
    guard let eventJsonString = result["event"] as? String,
          let eventData = eventJsonString.data(using: .utf8),
          let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
        os_log(.error, "Invalid sign result format - missing event JSON")
        return nil
    }

    // Parse event fields
    guard let createdAt = eventDict["created_at"] as? Int,
          let kind = eventDict["kind"] as? Int,
          let tags = eventDict["tags"] as? [[String]],
          let content = eventDict["content"] as? String,
          let id = eventDict["id"] as? String,
          let sig = eventDict["sig"] as? String,
          let pubkey = eventDict["pubkey"] as? String else {
        os_log(.error, "Invalid sign result format - missing fields")
        return nil
    }

    let signedEvent = SignedEvent(
        created_at: createdAt,
        kind: kind,
        tags: tags,
        content: content,
        id: id,
        sig: sig,
        pubkey: pubkey
    )

    return .signedEvent(signedEvent)
}

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
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
