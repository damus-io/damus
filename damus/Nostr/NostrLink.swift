//
//  NostrLink.swift
//  damus
//
//  Created by William Casarin on 2022-05-05.
//

import Foundation


enum NostrLink: Equatable {
    case ref(ReferencedId)
    case filter(NostrFilter)
}

func encode_pubkey_uri(_ ref: ReferencedId) -> String {
    return "p:" + ref.ref_id
}

// TODO: bech32 and relay hints
func encode_event_id_uri(_ ref: ReferencedId) -> String {
    return "e:" + ref.ref_id
}

func parse_nostr_ref_uri_type(_ p: Parser) -> String? {
    if parse_char(p, "p") {
        return "p"
    }
    
    if parse_char(p, "e") {
        return "e"
    }
    
    return nil
}

func parse_hexstr(_ p: Parser, len: Int) -> String? {
    var i: Int = 0
    
    if len % 2 != 0 {
        return nil
    }
    
    let start = p.pos
    
    while i < len {
        guard parse_hex_char(p) != nil else {
            p.pos = start
            return nil
        }
        i += 1
    }
    
    return String(substring(p.str, start: start, end: p.pos))
}

func parse_nostr_ref_uri(_ p: Parser) -> ReferencedId? {
    let start = p.pos
    
    if !parse_str(p, "nostr:") {
        return nil
    }
    
    guard let typ = parse_nostr_ref_uri_type(p) else {
        p.pos = start
        return nil
    }
    
    if !parse_char(p, ":") {
        p.pos = start
        return nil
    }
    
    guard let pk = parse_hexstr(p, len: 64) else {
        p.pos = start
        return nil
    }
    
    // TODO: parse relays from nostr uris
    return ReferencedId(ref_id: pk, relay_id: nil, key: typ)
}

func decode_universal_link(_ s: String) -> NostrLink? {
    var uri = s.replacingOccurrences(of: "https://damus.io/r/", with: "")
    uri = uri.replacingOccurrences(of: "https://damus.io/", with: "")
    uri = uri.replacingOccurrences(of: "/", with: "")
    
    guard let decoded = try? bech32_decode(uri) else {
        return nil
    }
    
    let h = hex_encode(decoded.data)
    
    if decoded.hrp == "note" {
        return .ref(ReferencedId(ref_id: h, relay_id: nil, key: "e"))
    } else if decoded.hrp == "npub" {
        return .ref(ReferencedId(ref_id: h, relay_id: nil, key: "p"))
    }
    // TODO: handle nprofile, etc
    
    return nil
}

func decode_nostr_bech32_uri(_ s: String) -> NostrLink? {
    guard let obj = Bech32Object.parse(s) else {
        return nil
    }
    
    switch obj {
    case .nsec(let privkey):
        guard let pubkey = privkey_to_pubkey(privkey: privkey) else {
            return nil
        }
        return .ref(ReferencedId(ref_id: pubkey, relay_id: nil, key: "p"))
    case .npub(let pubkey):
        return .ref(ReferencedId(ref_id: pubkey, relay_id: nil, key: "p"))
    case .note(let id):
        return .ref(ReferencedId(ref_id: id, relay_id: nil, key: "e"))
    }
}

func decode_nostr_uri(_ s: String) -> NostrLink? {
    if s.starts(with: "https://damus.io/") {
        return decode_universal_link(s)
    }

    var uri = s.replacingOccurrences(of: "nostr://", with: "")
    uri = uri.replacingOccurrences(of: "nostr:", with: "")
    
    let parts = uri.split(separator: ":")
        .reduce(into: Array<String>()) { acc, str in
            guard let decoded = str.removingPercentEncoding else {
                return
            }
            acc.append(decoded)
            return
        }
    
    if tag_is_hashtag(parts) {
        return .filter(NostrFilter.filter_hashtag([parts[1].lowercased()]))
    }
    
    if let rid = tag_to_refid(parts) {
        return .ref(rid)
    }
    
    guard parts.count == 1 else {
        return nil
    }
    
    let part = parts[0]
    
    return decode_nostr_bech32_uri(part)
}
