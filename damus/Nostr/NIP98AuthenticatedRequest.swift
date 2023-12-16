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

func make_nip98_authenticated_request(method: HTTPMethod, url: URL, payload: Data, auth_keypair: Keypair) async throws -> (data: Data, response: URLResponse) {
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    request.httpBody = payload
    
    let payload_hash = sha256(payload)
    let payload_hash_hex = payload_hash.map({ String(format: "%02hhx", $0) }).joined()
    
    let auth_note = NdbNote(
        content: "",
        keypair: auth_keypair,
        kind: 27235,
        tags: [
            ["u", url.absoluteString],
            ["method", method.rawValue],
            ["payload", payload_hash_hex]
        ],
        createdAt: UInt32(Date().timeIntervalSince1970)
    )
    let auth_note_json_data: Data = try JSONEncoder().encode(auth_note)
    let auth_note_base64: String = base64_encode(auth_note_json_data.bytes)
    
    request.setValue("Nostr " + auth_note_base64, forHTTPHeaderField: "Authorization")
    return try await URLSession.shared.data(for: request)
}
