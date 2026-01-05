//
//  NostrSignerResponse.swift
//  damus
//
//  NIP-55 iOS Extension: Builds callback URLs to return results to external apps.
//

import Foundation

/// Builds callback responses for NIP-55 signing requests.
///
/// After processing a signing request, Damus opens the callback URL with
/// the result appended as query parameters. Existing query parameters are preserved.
///
/// ## Success Response
/// ```
/// primal://nostrsigner?result=<hex_sig>&event=<url_encoded_json>
/// ```
///
/// ## Error Response
/// ```
/// primal://nostrsigner?error=<message>&rejected=true
/// ```
enum NostrSignerResponse {

    // MARK: - Success Responses

    /// Builds a success callback URL for a sign_event request.
    ///
    /// - Parameters:
    ///   - request: The original signing request.
    ///   - signature: The signature (hex-encoded).
    ///   - signedEventJson: The full signed event as JSON (optional).
    /// - Returns: The callback URL with result parameters.
    static func signEventSuccess(
        request: NostrSignerRequest,
        signature: String,
        signedEventJson: String?
    ) -> URL? {
        var components = URLComponents(url: request.callbackUrl, resolvingAgainstBaseURL: false)

        // Preserve existing query items
        var queryItems = components?.queryItems ?? []

        // Include the hex signature as result (NIP-55 compatible)
        queryItems.append(URLQueryItem(name: "result", value: signature))

        // Include full event if requested and available
        if request.returnType == .event, let eventJson = signedEventJson {
            // URL-encode the JSON for NIP-55 compatibility
            // compressionType=gzip would use "Signer1" + base64(gzip(json)) but we default to none
            queryItems.append(URLQueryItem(name: "event", value: eventJson))
        }

        components?.queryItems = queryItems
        return components?.url
    }

    /// Builds a success callback URL for a get_public_key request.
    ///
    /// - Parameters:
    ///   - request: The original request.
    ///   - pubkey: The user's public key.
    /// - Returns: The callback URL with the public key.
    static func publicKeySuccess(
        request: NostrSignerRequest,
        pubkey: Pubkey
    ) -> URL? {
        var components = URLComponents(url: request.callbackUrl, resolvingAgainstBaseURL: false)

        // Preserve existing query items
        var queryItems = components?.queryItems ?? []

        // Return pubkey as hex (NIP-55 compatible)
        queryItems.append(URLQueryItem(name: "result", value: pubkey.hex()))

        components?.queryItems = queryItems
        return components?.url
    }

    /// Builds a success callback URL for encrypt/decrypt operations.
    ///
    /// - Parameters:
    ///   - request: The original request.
    ///   - result: The encrypted/decrypted content (ciphertext or plaintext).
    /// - Returns: The callback URL with the result.
    ///
    /// - Note: The result is passed directly as a string. URLComponents handles
    ///   URL-encoding automatically, matching NIP-55 behavior.
    static func cryptoSuccess(
        request: NostrSignerRequest,
        result: String
    ) -> URL? {
        var components = URLComponents(url: request.callbackUrl, resolvingAgainstBaseURL: false)

        var queryItems = components?.queryItems ?? []

        // Pass result directly - URLComponents handles URL-encoding
        queryItems.append(URLQueryItem(name: "result", value: result))

        components?.queryItems = queryItems
        return components?.url
    }

    // MARK: - Error Responses

    /// Builds an error callback URL.
    ///
    /// - Parameters:
    ///   - request: The original request.
    ///   - message: The error message.
    ///   - rejected: Whether this was a user rejection (vs. a processing error).
    /// - Returns: The callback URL with error parameters.
    static func error(
        request: NostrSignerRequest,
        message: String,
        rejected: Bool = false
    ) -> URL? {
        var components = URLComponents(url: request.callbackUrl, resolvingAgainstBaseURL: false)

        var queryItems = components?.queryItems ?? []

        // URL-encode the error message
        queryItems.append(URLQueryItem(name: "error", value: message))

        if rejected {
            queryItems.append(URLQueryItem(name: "rejected", value: "true"))
        }

        components?.queryItems = queryItems
        return components?.url
    }

    /// Builds a rejection callback URL (user denied the request).
    ///
    /// - Parameter request: The original request.
    /// - Returns: The callback URL indicating rejection.
    static func rejected(request: NostrSignerRequest) -> URL? {
        return error(request: request, message: "User rejected the request", rejected: true)
    }

    /// Builds an error callback for when the user is not logged in.
    ///
    /// - Parameter request: The original request.
    /// - Returns: The callback URL indicating no keypair available.
    static func notLoggedIn(request: NostrSignerRequest) -> URL? {
        return error(request: request, message: "No keypair available", rejected: false)
    }

    /// Builds an error callback for unsupported operations.
    ///
    /// - Parameter request: The original request.
    /// - Returns: The callback URL indicating unsupported method.
    static func unsupportedMethod(request: NostrSignerRequest) -> URL? {
        return error(
            request: request,
            message: "Method '\(request.method.rawValue)' is not supported",
            rejected: false
        )
    }

    /// Builds an error callback for invalid request content.
    ///
    /// - Parameter request: The original request.
    /// - Returns: The callback URL indicating invalid content.
    static func invalidContent(request: NostrSignerRequest) -> URL? {
        return error(request: request, message: "Invalid request content", rejected: false)
    }
}
