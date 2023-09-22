//
//  NostrLink.swift
//  damus
//
//  Created by William Casarin on 2022-05-05.
//

import Foundation


enum NostrLink: Equatable {
    case ref(RefId)
    case filter(NostrFilter)
    case script([UInt8])
}

func encode_pubkey_uri(_ pubkey: Pubkey) -> String {
    return "p:" + pubkey.hex()
}

// TODO: bech32 and relay hints
func encode_event_id_uri(_ noteid: NoteId) -> String {
    return "e:" + noteid.hex()
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

func decode_universal_link(_ s: String) -> NostrLink? {
    var uri = s.replacingOccurrences(of: "https://damus.io/r/", with: "")
    uri = uri.replacingOccurrences(of: "https://damus.io/", with: "")
    uri = uri.replacingOccurrences(of: "/", with: "")
    
    guard let decoded = try? bech32_decode(uri),
          decoded.data.count == 32
    else {
        return nil
    }

    if decoded.hrp == "note" {
        return .ref(.event(NoteId(decoded.data)))
    } else if decoded.hrp == "npub" {
        return .ref(.pubkey(Pubkey(decoded.data)))
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
        guard let pubkey = privkey_to_pubkey(privkey: privkey) else { return nil }
        return .ref(.pubkey(pubkey))
    case .npub(let pubkey):
        return .ref(.pubkey(pubkey))
    case .note(let id):
        return .ref(.event(id))
    case .nscript(let data):
        return .script(data)
    }
}

func decode_nostr_uri(_ s: String) -> NostrLink? {
    if s.starts(with: "https://damus.io/") {
        return decode_universal_link(s)
    }

    var uri = s
    uri = uri.replacingOccurrences(of: "nostr://", with: "")
    uri = uri.replacingOccurrences(of: "nostr:", with: "")

    // Fix for non-latin characters resulting in second colon being encoded
    uri = uri.replacingOccurrences(of: "damus:t%3A", with: "t:")
    
    uri = uri.replacingOccurrences(of: "damus://", with: "")
    uri = uri.replacingOccurrences(of: "damus:", with: "")
    
    let parts = uri.split(separator: ":")
        .reduce(into: Array<String>()) { acc, str in
            guard let decoded = str.removingPercentEncoding else {
                return
            }
            acc.append(decoded)
            return
        }

    if parts.count >= 2 && parts[0] == "t" {
        return .filter(NostrFilter(hashtag: [parts[1].lowercased()]))
    }

    guard parts.count == 1 else {
        return nil
    }

    let part = parts[0]
    
    return decode_nostr_bech32_uri(part)
}
