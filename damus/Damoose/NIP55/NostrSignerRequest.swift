//
//  NostrSignerRequest.swift
//  damus
//
//  NIP-55 iOS Extension: Parses incoming nostrsigner:// URLs from external apps.
//

import Foundation

/// The return type for sign_event operations.
enum SignerReturnType: String {
    /// Return only the signature.
    case signature
    /// Return the full signed event JSON.
    case event
}

/// The compression type for response content.
enum SignerCompressionType: String {
    /// No compression, URL-encoded JSON.
    case none
    /// Gzip compressed: "Signer1" + base64(gzip(json)).
    case gzip
}

/// A signing request from an external app via NIP-55 URL scheme.
///
/// Parses URLs of the format:
/// ```
/// nostrsigner:<url_encoded_content>?type=sign_event&callbackUrl=primal://...
/// ```
///
/// ## Supported Methods
/// - `get_public_key`: Returns the user's public key
/// - `sign_event`: Signs a nostr event
/// - `nip04_encrypt`/`nip04_decrypt`: NIP-04 encryption operations
/// - `nip44_encrypt`/`nip44_decrypt`: NIP-44 encryption operations
/// - `decrypt_zap_event`: Decrypts zap events
struct NostrSignerRequest: Equatable {

    // MARK: - Method Enum

    /// The operation type requested by the external app.
    enum Method: String, CaseIterable {
        case getPublicKey = "get_public_key"
        case signEvent = "sign_event"
        case nip04Encrypt = "nip04_encrypt"
        case nip04Decrypt = "nip04_decrypt"
        case nip44Encrypt = "nip44_encrypt"
        case nip44Decrypt = "nip44_decrypt"
        case decryptZapEvent = "decrypt_zap_event"

        /// Human-readable description for logging/debugging.
        var description: String {
            switch self {
            case .getPublicKey: return "Get Public Key"
            case .signEvent: return "Sign Event"
            case .nip04Encrypt: return "NIP-04 Encrypt"
            case .nip04Decrypt: return "NIP-04 Decrypt"
            case .nip44Encrypt: return "NIP-44 Encrypt"
            case .nip44Decrypt: return "NIP-44 Decrypt"
            case .decryptZapEvent: return "Decrypt Zap"
            }
        }
    }

    // MARK: - Properties

    /// The operation to perform.
    let method: Method

    /// The content payload (URL-decoded).
    /// For sign_event: JSON-encoded unsigned event.
    /// For encrypt: plaintext to encrypt.
    /// For decrypt: ciphertext to decrypt.
    let content: Data?

    /// The URL to call back with the result.
    let callbackUrl: URL

    /// How to return sign_event results.
    let returnType: SignerReturnType

    /// Response compression type.
    let compressionType: SignerCompressionType

    /// Target pubkey for encryption/decryption operations.
    let targetPubkey: Pubkey?

    /// Original requesting app identifier (derived from callback URL).
    var clientId: String {
        callbackUrl.host ?? callbackUrl.scheme ?? "unknown"
    }

    // MARK: - Parsing

    /// Parses a nostrsigner:// URL into a request.
    ///
    /// - Parameter url: The incoming URL to parse.
    /// - Returns: A parsed request, or nil if the URL is invalid.
    static func parse(url: URL) -> NostrSignerRequest? {
        guard url.scheme == "nostrsigner" else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // Extract query parameters
        let queryItems = components.queryItems ?? []

        // Method is required
        guard let typeString = queryItems.first(where: { $0.name == "type" })?.value,
              let method = Method(rawValue: typeString) else {
            return nil
        }

        // Callback URL is required
        guard let callbackString = queryItems.first(where: { $0.name == "callbackUrl" })?.value,
              let callbackUrl = URL(string: callbackString) else {
            return nil
        }

        // Validate callback URL scheme (security: no file://, javascript://, etc.)
        guard let scheme = callbackUrl.scheme,
              isAllowedCallbackScheme(scheme) else {
            return nil
        }

        // Optional parameters
        let returnTypeString = queryItems.first(where: { $0.name == "returnType" })?.value ?? "signature"
        let returnType = SignerReturnType(rawValue: returnTypeString) ?? .signature

        let compressionString = queryItems.first(where: { $0.name == "compressionType" })?.value ?? "none"
        let compressionType = SignerCompressionType(rawValue: compressionString) ?? .none

        // Target pubkey for encrypt/decrypt operations
        var targetPubkey: Pubkey? = nil
        if let pubkeyHex = queryItems.first(where: { $0.name == "pubkey" })?.value {
            targetPubkey = hex_decode_pubkey(pubkeyHex)
        }

        // Content is in the URL path (after the scheme:)
        // URL format: nostrsigner:<content>?params...
        let content = parseContent(from: components)

        return NostrSignerRequest(
            method: method,
            content: content,
            callbackUrl: callbackUrl,
            returnType: returnType,
            compressionType: compressionType,
            targetPubkey: targetPubkey
        )
    }

    // MARK: - Private Helpers

    /// Extracts and URL-decodes the content from the URL path.
    private static func parseContent(from components: URLComponents) -> Data? {
        // The content is after "nostrsigner:"
        // URLComponents.path will be empty if content is in host position
        var rawContent = components.path

        // If path is empty, try the host (some URL parsers put it there)
        if rawContent.isEmpty {
            rawContent = components.host ?? ""
        }

        // Remove any leading slashes
        rawContent = rawContent.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !rawContent.isEmpty else {
            return nil
        }

        // URL-decode the content (NIP-55 compatible)
        guard let urlDecoded = rawContent.removingPercentEncoding,
              let data = urlDecoded.data(using: .utf8) else {
            return nil
        }
        return data
    }

    /// Checks if a callback URL scheme is allowed.
    ///
    /// Prevents security issues with dangerous schemes.
    private static func isAllowedCallbackScheme(_ scheme: String) -> Bool {
        // Block dangerous schemes and nostrsigner (re-entrancy prevention)
        let blocked = ["file", "javascript", "data", "about", "blob", "nostrsigner"]
        return !blocked.contains(scheme.lowercased())
    }
}

// MARK: - Content Parsing Helpers

extension NostrSignerRequest {

    /// Attempts to parse the content as an unsigned event JSON.
    ///
    /// - Returns: The parsed unsigned event, or nil if parsing fails.
    func parseAsUnsignedEvent() -> UnsignedEvent? {
        guard let content = content else {
            return nil
        }

        return try? JSONDecoder().decode(UnsignedEvent.self, from: content)
    }

    /// Returns the content as a UTF-8 string (for encrypt/decrypt operations).
    var contentString: String? {
        guard let content = content else {
            return nil
        }
        return String(data: content, encoding: .utf8)
    }
}
