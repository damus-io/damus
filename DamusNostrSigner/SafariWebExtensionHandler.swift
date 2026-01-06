//
//  SafariWebExtensionHandler.swift
//  DamusNostrSigner
//
//  NIP-07 Safari Web Extension native handler.
//  Delegates signing to the main Damus app via nostrsigner:// URL scheme (DIP-05).
//

import SafariServices
import os.log

/// Native message handler for the Damus NIP-07 Safari extension.
///
/// For `getPublicKey`, reads directly from shared keychain (fast, no app switch).
/// For `signEvent` and crypto operations, delegates to Damus app via DIP-05 URL scheme.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    // MARK: - Logging

    private let logger = Logger(subsystem: "io.damus.DamusNostrSigner", category: "handler")

    // MARK: - Shared Keychain Access

    private static let keychainService = "damus"
    private static let pubkeyDefaultsKey = "pubkey"

    // MARK: - NSExtensionRequestHandling

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any] else {
            logger.error("Invalid extension request")
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        logger.info("Received NIP-07 request: \(message["method"] as? String ?? "unknown")")

        let response = handleMessage(message)

        let responseItem = NSExtensionItem()
        responseItem.userInfo = [SFExtensionMessageKey: response]

        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: [String: Any]) -> [String: Any] {
        guard let method = message["method"] as? String else {
            return ["error": "Missing method"]
        }

        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "getPublicKey":
            return handleGetPublicKey()

        case "signEvent":
            // For signing, we need user approval - delegate to DIP-05
            return ["error": "signEvent requires app approval - use Damus app"]
            // TODO: Implement DIP-05 delegation flow

        case "nip04.encrypt", "nip04.decrypt", "nip44.encrypt", "nip44.decrypt":
            return ["error": "Encryption requires app approval - use Damus app"]
            // TODO: Implement DIP-05 delegation flow

        default:
            return ["error": "Unsupported method: \(method)"]
        }
    }

    // MARK: - NIP-07 Methods

    /// Returns the user's public key from shared keychain.
    /// This is a read-only operation that doesn't require user approval.
    private func handleGetPublicKey() -> [String: Any] {
        // Read pubkey from shared UserDefaults (App Group)
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.jb55.damus2"),
              let pubkeyHex = sharedDefaults.string(forKey: Self.pubkeyDefaultsKey) else {
            // Fall back to standard UserDefaults
            guard let pubkeyHex = UserDefaults.standard.string(forKey: Self.pubkeyDefaultsKey) else {
                return ["error": "Not logged in to Damus"]
            }
            return ["result": pubkeyHex]
        }

        return ["result": pubkeyHex]
    }
}
