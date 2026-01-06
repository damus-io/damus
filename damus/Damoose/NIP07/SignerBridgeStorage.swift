//
//  SignerBridgeStorage.swift
//  damus
//
//  Shared storage for Safari extension ↔ Damus app communication.
//  Uses App Group UserDefaults for cross-process access.
//

import Foundation

/// Shared storage for NIP-07 Safari extension to communicate with Damus app.
///
/// The Safari extension cannot receive URL callbacks directly. Instead:
/// 1. Extension stores request with unique ID
/// 2. Extension returns URL for JS to open (switches to Damus)
/// 3. Damus processes request, stores result keyed by ID
/// 4. JS polls extension, which checks for result
///
/// ## Usage (Extension side)
/// ```swift
/// let requestId = SignerBridgeStorage.storeRequest(event: eventJson, origin: "snort.social")
/// return ["action": "openUrl", "url": url, "requestId": requestId]
/// // Later, when polled:
/// if let result = SignerBridgeStorage.getResult(requestId: requestId) {
///     return result
/// }
/// ```
///
/// ## Usage (Damus app side)
/// ```swift
/// // After signing
/// if let requestId = request.extensionRequestId {
///     SignerBridgeStorage.storeResult(requestId: requestId, result: signedEvent)
/// }
/// ```
enum SignerBridgeStorage {

    // MARK: - Constants

    /// App Group identifier for shared storage.
    private static let appGroup = "group.com.jb55.damus2"

    /// Key prefix for pending requests.
    private static let requestPrefix = "signer_request_"

    /// Key prefix for results.
    private static let resultPrefix = "signer_result_"

    /// How long to keep results before cleanup (5 minutes).
    private static let resultTTL: TimeInterval = 300

    // MARK: - Request Storage (Extension → App)

    /// Stores a signing request and returns its unique ID.
    ///
    /// - Parameters:
    ///   - eventJson: The unsigned event JSON to sign.
    ///   - origin: The website origin requesting the signature.
    /// - Returns: Unique request ID, or nil if storage failed.
    static func storeRequest(eventJson: String, origin: String) -> String? {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            return nil
        }

        let requestId = UUID().uuidString
        let request: [String: Any] = [
            "event": eventJson,
            "origin": origin,
            "timestamp": Date().timeIntervalSince1970
        ]

        defaults.set(request, forKey: requestPrefix + requestId)
        defaults.synchronize()

        return requestId
    }

    /// Retrieves a pending request by ID.
    ///
    /// - Parameter requestId: The request ID.
    /// - Returns: The request details, or nil if not found.
    static func getRequest(requestId: String) -> (eventJson: String, origin: String)? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let request = defaults.dictionary(forKey: requestPrefix + requestId),
              let eventJson = request["event"] as? String,
              let origin = request["origin"] as? String else {
            return nil
        }

        return (eventJson, origin)
    }

    /// Removes a pending request.
    ///
    /// - Parameter requestId: The request ID to remove.
    static func removeRequest(requestId: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            return
        }
        defaults.removeObject(forKey: requestPrefix + requestId)
        defaults.synchronize()
    }

    // MARK: - Result Storage (App → Extension)

    /// Stores a signing result for the extension to retrieve.
    ///
    /// - Parameters:
    ///   - requestId: The request ID this result is for.
    ///   - signedEventJson: The signed event JSON, or nil if rejected/error.
    ///   - signature: The signature hex string.
    ///   - error: Error message if signing failed.
    static func storeResult(
        requestId: String,
        signedEventJson: String? = nil,
        signature: String? = nil,
        error: String? = nil
    ) {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            return
        }

        var result: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970
        ]

        if let signedEventJson = signedEventJson {
            result["event"] = signedEventJson
        }
        if let signature = signature {
            result["signature"] = signature
        }
        if let error = error {
            result["error"] = error
        }

        defaults.set(result, forKey: resultPrefix + requestId)
        defaults.synchronize()

        // Clean up the original request
        removeRequest(requestId: requestId)
    }

    /// Retrieves and removes a signing result.
    ///
    /// - Parameter requestId: The request ID.
    /// - Returns: The result dictionary, or nil if not ready.
    static func getResult(requestId: String) -> [String: Any]? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let result = defaults.dictionary(forKey: resultPrefix + requestId) else {
            return nil
        }

        // Remove after reading (one-time retrieval)
        defaults.removeObject(forKey: resultPrefix + requestId)
        defaults.synchronize()

        return result
    }

    /// Checks if a result is available without consuming it.
    ///
    /// - Parameter requestId: The request ID.
    /// - Returns: true if a result is available.
    static func hasResult(requestId: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            return false
        }
        return defaults.object(forKey: resultPrefix + requestId) != nil
    }

    // MARK: - Cleanup

    /// Removes stale requests and results older than TTL.
    static func cleanup() {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            return
        }

        let now = Date().timeIntervalSince1970
        let allKeys = defaults.dictionaryRepresentation().keys

        for key in allKeys {
            guard key.hasPrefix(requestPrefix) || key.hasPrefix(resultPrefix) else {
                continue
            }
            guard let dict = defaults.dictionary(forKey: key),
                  let timestamp = dict["timestamp"] as? TimeInterval else {
                continue
            }
            if now - timestamp > resultTTL {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.synchronize()
    }
}
