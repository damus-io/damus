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
    
    guard let id = parse_hexstr(p, len: 64) else {
        p.pos = start
        return nil
    }
    
    return ReferencedId(ref_id: id, relay_id: nil, key: typ.ref)
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

