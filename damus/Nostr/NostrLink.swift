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
        case .naddr(let naddr):
            return .ref(.naddr(naddr))
        case .nevent(let nevent):
            return .ref(.event(nevent.noteid))
        case .nprofile(let nprofile):
            return .ref(.pubkey(nprofile.author))
        case .nrelay(_):
            return .none
        }
}

func decode_nostr_uri(_ s: String) -> NostrLink? {
    let uri = remove_nostr_uri_prefix(s)
    
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
