//
//  SafariWebExtensionHandler.swift
//  DamusNostrSigner
//
//  NIP-07 Safari Web Extension native handler.
//  Delegates signing to the main Damus app via DIP-05 URL scheme.
//

import SafariServices
import os.log

/// Native message handler for the Damus NIP-07 Safari extension.
///
/// For `getPublicKey`, reads directly from shared keychain (fast, no app switch).
/// For `signEvent`, delegates to Damus app via DIP-05 URL scheme using shared storage bridge.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    // MARK: - Logging

    private let logger = Logger(subsystem: "io.damus.DamusNostrSigner", category: "handler")

    // MARK: - Shared Storage Access

    private static let appGroup = "group.com.damus"
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
            return handleSignEvent(params: params)

        case "checkResult":
            return handleCheckResult(params: params)

        case "nip04.encrypt", "nip04.decrypt", "nip44.encrypt", "nip44.decrypt":
            return ["error": "Encryption requires app approval - use Damus app"]

        default:
            return ["error": "Unsupported method: \(method)"]
        }
    }

    // MARK: - NIP-07 Methods

    /// Returns the user's public key from shared storage.
    private func handleGetPublicKey() -> [String: Any] {
        guard let sharedDefaults = UserDefaults(suiteName: Self.appGroup),
              let pubkeyHex = sharedDefaults.string(forKey: Self.pubkeyDefaultsKey) else {
            return ["error": "Not logged in to Damus"]
        }

        return ["result": pubkeyHex]
    }

    /// Handles signEvent by storing request and returning URL for JS to open.
    private func handleSignEvent(params: [String: Any]) -> [String: Any] {
        // Get the event to sign
        guard let event = params["event"] else {
            return ["error": "Missing event parameter"]
        }

        // Convert event to JSON string
        let eventJson: String
        if let eventString = event as? String {
            eventJson = eventString
        } else if let eventDict = event as? [String: Any] {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: eventDict),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return ["error": "Failed to serialize event"]
            }
            eventJson = jsonString
        } else {
            return ["error": "Invalid event format"]
        }

        // Get origin from params (set by content script)
        let origin = params["origin"] as? String ?? "unknown"

        // Store the request in shared storage
        guard let requestId = storeRequest(eventJson: eventJson, origin: origin) else {
            return ["error": "Failed to store request"]
        }

        // Build nostrsigner:// URL
        guard let url = buildSignerUrl(eventJson: eventJson, requestId: requestId, origin: origin) else {
            return ["error": "Failed to build signer URL"]
        }

        logger.info("Created sign request \(requestId) for origin \(origin)")

        // Return action for JS to open the URL
        return [
            "action": "openUrl",
            "url": url,
            "requestId": requestId
        ]
    }

    /// Checks if a signing result is ready.
    private func handleCheckResult(params: [String: Any]) -> [String: Any] {
        guard let requestId = params["requestId"] as? String else {
            return ["error": "Missing requestId"]
        }

        guard let result = getResult(requestId: requestId) else {
            // Not ready yet
            return ["pending": true]
        }

        // Check for error
        if let error = result["error"] as? String {
            return ["error": error]
        }

        // Return the signed event
        if let signedEventJson = result["event"] as? String {
            // Parse the JSON to return as object
            if let data = signedEventJson.data(using: .utf8),
               let eventDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return ["result": eventDict]
            }
            return ["result": signedEventJson]
        }

        // Return just signature if no full event
        if let signature = result["signature"] as? String {
            return ["result": ["sig": signature]]
        }

        return ["error": "Invalid result format"]
    }

    // MARK: - Shared Storage Bridge

    /// Stores a signing request in shared UserDefaults.
    private func storeRequest(eventJson: String, origin: String) -> String? {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else {
            logger.error("Failed to access app group defaults")
            return nil
        }

        let requestId = UUID().uuidString
        let request: [String: Any] = [
            "event": eventJson,
            "origin": origin,
            "timestamp": Date().timeIntervalSince1970
        ]

        defaults.set(request, forKey: "signer_request_\(requestId)")
        defaults.synchronize()

        return requestId
    }

    /// Retrieves a signing result from shared UserDefaults.
    private func getResult(requestId: String) -> [String: Any]? {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let result = defaults.dictionary(forKey: "signer_result_\(requestId)") else {
            return nil
        }

        // Remove after reading (one-time retrieval)
        defaults.removeObject(forKey: "signer_result_\(requestId)")
        defaults.synchronize()

        return result
    }

    // MARK: - URL Building

    /// Builds a nostrsigner:// URL for the signing request.
    private func buildSignerUrl(eventJson: String, requestId: String, origin: String) -> String? {
        // URL-encode the event JSON
        guard let encodedEvent = eventJson.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) else {
            return nil
        }

        // Build callback URL - we use a special scheme that indicates extension callback
        // The main app will store result in shared storage instead of opening URL
        let callbackUrl = "damus-extension://callback"
        guard let encodedCallback = callbackUrl.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else {
            return nil
        }

        // Build the nostrsigner URL
        // Format: nostrsigner:<event>?type=sign_event&callbackUrl=<url>&extensionRequestId=<id>
        var url = "nostrsigner:\(encodedEvent)"
        url += "?type=sign_event"
        url += "&callbackUrl=\(encodedCallback)"
        url += "&extensionRequestId=\(requestId)"
        url += "&returnType=event"

        return url
    }
}
