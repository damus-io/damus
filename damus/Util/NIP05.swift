//
//  NIP05.swift
//  damus
//
//  Created by William Casarin on 2023-01-04.
//

import Foundation

struct NIP05: Equatable {
    let username: String
    let host: String
    
    var url: URL? {
        URL(string: "https://\(host)/.well-known/nostr.json?name=\(username)")
    }
    
    var siteUrl: URL? {
        URL(string: "https://\(host)")
    }
    
    static func parse(_ nip05: String) -> NIP05? {
        let parts = nip05.split(separator: "@")
        guard parts.count == 2 else {
            return nil
        }
        return NIP05(username: String(parts[0]), host: String(parts[1]))
    }
}


struct NIP05Response: Decodable {
    let names: [String: Pubkey]
}

func fetch_nip05(nip05: NIP05) async -> NIP05Response? {
    guard let url = nip05.url else {
        return nil
    }

    print("fetching nip05 \(url.absoluteString)")
    guard let ret = try? await URLSession.shared.data(from: url) else {
        return nil
    }
    let dat = ret.0
    
    guard let decoded = try? JSONDecoder().decode(NIP05Response.self, from: dat) else {
        return nil
    }
    
    return decoded
}

func validate_nip05(pubkey: Pubkey, nip05_str: String) async -> NIP05? {
    guard let nip05 = NIP05.parse(nip05_str) else {
        return nil
    }
    
    guard let decoded = await fetch_nip05(nip05: nip05) else {
        return nil
    }
    
    guard let stored_pk = decoded.names[nip05.username] else {
        return nil
    }
    
    guard stored_pk == pubkey else {
        return nil
    }
    
    return nip05
}
