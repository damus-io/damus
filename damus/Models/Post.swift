//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-05-07.
//

import Foundation

struct NostrPost {
    let content: String
    let references: [ReferencedId]
}

// TODO: parse nostr:{e,p}:pubkey uris as well
func parse_post_mention_type(_ p: Parser) -> MentionType? {
    if parse_char(p, "@") {
        return .pubkey
    }
    
    if parse_char(p, "&") {
        return .event
    }
    
    return nil
}

func parse_post_reference(_ p: Parser) -> ReferencedId? {
    let start = p.pos
    
    guard let typ = parse_post_mention_type(p) else {
        return parse_nostr_ref_uri(p)
    }
    
    if let ref = parse_post_mention(p, mention_type: typ) {
        return ref
    }
    
    p.pos = start
    
    return nil
}

func is_bech32_char(_ c: Character) -> Bool {
    let contains = "qpzry9x8gf2tvdw0s3jn54khce6mua7l".contains(c)
    return contains
}

func parse_post_mention(_ p: Parser, mention_type: MentionType) -> ReferencedId? {
    if let id = parse_hexstr(p, len: 64) {
        return ReferencedId(ref_id: id, relay_id: nil, key: mention_type.ref)
    } else if let bech32_ref = parse_post_bech32_mention(p) {
        return bech32_ref
    } else {
        return nil
    }
}

func parse_post_bech32_mention(_ p: Parser) -> ReferencedId? {
    let start = p.pos
    if parse_str(p, "note") {
    } else if parse_str(p, "npub") {
    } else if parse_str(p, "nsec") {
    } else {
        return nil
    }
    
    if !parse_char(p, "1") {
        p.pos = start
        return nil
    }
    
    var end = p.pos
    if consume_until(p, match: { c in !is_bech32_char(c) }) {
        end = p.pos
    } else {
        p.pos = start
        return nil
    }
    
    let sliced = String(substring(p.str, start: start, end: end))
    guard let decoded = try? bech32_decode(sliced) else {
        p.pos = start
        return nil
    }
    
    let hex = hex_encode(decoded.data)
    switch decoded.hrp {
    case "note":
        return ReferencedId(ref_id: hex, relay_id: nil, key: "e")
    case "npub":
        return ReferencedId(ref_id: hex, relay_id: nil, key: "p")
    case "nsec":
        guard let pubkey = privkey_to_pubkey(privkey: hex) else {
            p.pos = start
            return nil
        }
        return ReferencedId(ref_id: pubkey, relay_id: nil, key: "p")
    default:
        p.pos = start
        return nil
    }
}

/// Return a list of tags
func parse_post_blocks(content: String) -> [PostBlock] {
    let p = Parser(pos: 0, str: content)
    var blocks: [PostBlock] = []
    var starting_from: Int = 0
    
    if content.count == 0 {
        return []
    }
    
    while p.pos < content.count {
        let pre_mention = p.pos
        if let reference = parse_post_reference(p) {
            blocks.append(parse_post_textblock(str: p.str, from: starting_from, to: pre_mention))
            blocks.append(.ref(reference))
            starting_from = p.pos
        } else if let hashtag = parse_hashtag(p) {
            blocks.append(parse_post_textblock(str: p.str, from: starting_from, to: pre_mention))
            blocks.append(.hashtag(hashtag))
            starting_from = p.pos
        } else {
            p.pos += 1
        }
    }
    
    blocks.append(parse_post_textblock(str: content, from: starting_from, to: content.count))
    
    return blocks
}

