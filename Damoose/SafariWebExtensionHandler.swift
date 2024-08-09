//
//  SafariWebExtensionHandler.swift
//  Damoose
//
//  Created by William Casarin on 8/5/24.
//

import SafariServices
import os.log

import Foundation
import os.log

enum DamooseRequest {
    case getPublicKey
    case signEvent(SignEventPayload)
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
        return .pubkey("32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")
    case .signEvent(_):
        return nil
    case .getRelays:
        return nil
    case .nip04_encrypt(_):
        return nil
    case .nip04_decrypt(_):
        return nil
    }
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
    }
}
