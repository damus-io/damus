//
//  NIP98AuthenticatedRequest.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-12-15.
//

import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

enum HTTPPayloadType: String {
    case json = "application/json"
    case binary = "application/octet-stream"
}

/// Creates a NIP-98 authentication event for HTTP requests.
///
/// This generates the Nostr event used for authenticating HTTP requests according to NIP-98.
/// The event includes the request URL, HTTP method, and optionally a payload hash.
///
/// - Parameters:
///   - method: The HTTP method (GET, POST, PUT, DELETE)
///   - url: The full URL being requested
///   - payload: Optional request body data to hash and include in the auth event
///   - auth_keypair: The keypair to sign the auth event with
/// - Returns: The NIP-98 authentication event, or nil if event creation fails
func create_nip98_auth_event(method: HTTPMethod, url: URL, payload: Data?, auth_keypair: Keypair) -> NdbNote? {
    var tag_pairs = [
        ["u", url.absoluteString],
        ["method", method.rawValue],
    ]
    
    if let payload {
        let payload_hash = sha256(payload)
        let payload_hash_hex = hex_encode(payload_hash)
        tag_pairs.append(["payload", payload_hash_hex])
    }
        
    return NdbNote(
        content: "",
        keypair: auth_keypair,
        kind: 27235,
        tags: tag_pairs,
        createdAt: UInt32(Date().timeIntervalSince1970)
    )
}

/// Makes an HTTP request authenticated with a pre-built NIP-98 event.
///
/// This overload accepts a pre-built and signed NIP-98 authentication event.
///
/// - Parameters:
///   - method: The HTTP method (GET, POST, PUT, DELETE)
///   - url: The full URL to request
///   - payload: Optional request body data
///   - payload_type: Optional Content-Type for the payload
///   - auth_note: The pre-built NIP-98 authentication event
/// - Returns: A tuple containing the response data and URLResponse
/// - Throws: Errors from URL loading or JSON encoding
func make_nip98_authenticated_request(method: HTTPMethod, url: URL, payload: Data?, payload_type: HTTPPayloadType?, auth_note: NdbNote) async throws -> (data: Data, response: URLResponse) {
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    request.httpBody = payload
    
    let auth_note_json_data: Data = try encode_json_data(auth_note)
    let auth_note_base64: String = base64_encode(auth_note_json_data.bytes)
    
    request.setValue("Nostr " + auth_note_base64, forHTTPHeaderField: "Authorization")
    if let payload_type {
        request.setValue(payload_type.rawValue, forHTTPHeaderField: "Content-Type")
    }
    return try await URLSession.shared.data(for: request)
}

/// Makes an HTTP request authenticated with NIP-98.
///
/// This function creates a NIP-98 authentication event and includes it in the request's
/// Authorization header as a base64-encoded Nostr event.
///
/// - Parameters:
///   - method: The HTTP method (GET, POST, PUT, DELETE)
///   - url: The full URL to request
///   - payload: Optional request body data
///   - payload_type: Optional Content-Type for the payload
///   - auth_keypair: The keypair to sign the auth event with
/// - Returns: A tuple containing the response data and URLResponse
/// - Throws: Errors from URL loading or JSON encoding
func make_nip98_authenticated_request(method: HTTPMethod, url: URL, payload: Data?, payload_type: HTTPPayloadType?, auth_keypair: Keypair) async throws -> (data: Data, response: URLResponse) {
    guard let auth_note = create_nip98_auth_event(method: method, url: url, payload: payload, auth_keypair: auth_keypair) else {
        throw URLError(.unknown)
    }

    return try await make_nip98_authenticated_request(method: method, url: url, payload: payload, payload_type: payload_type, auth_note: auth_note)
}
