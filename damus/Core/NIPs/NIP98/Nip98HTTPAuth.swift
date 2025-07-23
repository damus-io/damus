//
//  Nip98HTTPAuth.swift
//  damus
//
//  Created by Fishcake on 2023/08/12.
//

import Foundation

func create_nip98_signature (keypair: Keypair, method: String, url: URL) -> String? {
    let tags = [
        ["u", url.standardized.absoluteString], // Ensure that we standardise the URL before extracting string value.
        ["method", method]
    ]
    
    guard let ev = NostrEvent(content: "", keypair: keypair, kind: NostrKind.http_auth.rawValue, tags: tags) else {
         return nil
    }

    let json = event_to_json(ev: ev)
    let base64Header = base64_encode(Array(json.utf8))
    return "Nostr " + base64Header // The returned value should be used in Authorization HTTP header
}
