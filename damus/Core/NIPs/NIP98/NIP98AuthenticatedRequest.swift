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

func make_nip98_authenticated_request(method: HTTPMethod, url: URL, payload: Data?, payload_type: HTTPPayloadType?, auth_keypair: Keypair) async throws -> (data: Data, response: URLResponse) {
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    request.httpBody = payload
    
    var tag_pairs = [
        ["u", url.absoluteString],
        ["method", method.rawValue],
    ]
    
    if let payload {
        let payload_hash = sha256(payload)
        let payload_hash_hex = hex_encode(payload_hash)
        tag_pairs.append(["payload", payload_hash_hex])
    }
        
    let auth_note = NdbNote(
        content: "",
        keypair: auth_keypair,
        kind: 27235,
        tags: tag_pairs,
        createdAt: UInt32(Date().timeIntervalSince1970)
    )

    let auth_note_json_data: Data = try encode_json_data(auth_note)
    let auth_note_base64: String = base64_encode(auth_note_json_data.bytes)
    
    request.setValue("Nostr " + auth_note_base64, forHTTPHeaderField: "Authorization")
    if let payload_type {
        request.setValue(payload_type.rawValue, forHTTPHeaderField: "Content-Type")
    }
    return try await URLSession.shared.data(for: request)
}
