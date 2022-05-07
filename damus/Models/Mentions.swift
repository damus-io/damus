//
//  Mentions.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import Foundation


enum MentionType {
    case pubkey
    case event
    
    var ref: String {
        switch self {
        case .pubkey:
            return "p"
        case .event:
            return "e"
        }
    }
}

struct Mention {
    let index: Int
    let type: MentionType
    let ref: ReferencedId
}

struct IdBlock: Identifiable {
    let id: String = UUID().description
    let block: Block
}

enum Block {
    case text(String)
    case mention(Mention)
    
    var is_text: Bool {
        if case .text = self {
            return true
        }
        return false
    }
    
    var is_mention: Bool {
        if case .mention = self {
            return true
        }
        return false
    }
}

func render_blocks(blocks: [Block]) -> String {
    return blocks.reduce("") { str, block in
        switch block {
        case .mention(let m):
            return str + "#[\(m.index)]"
        case .text(let txt):
            return str + txt
        }
    }
}

func parse_textblock(str: String, from: Int, to: Int) -> Block {
    return .text(String(substring(str, start: from, end: to)))
}

func parse_mentions(content: String, tags: [[String]]) -> [Block] {
    let p = Parser(pos: 0, str: content)
    var blocks: [Block] = []
    var starting_from: Int = 0
    
    while p.pos < content.count {
        if (!consume_until(p, match: { $0 == "#" })) {
            blocks.append(parse_textblock(str: p.str, from: starting_from, to: p.str.count))
            return blocks
        }
        
        let pre_mention = p.pos
        if let mention = parse_mention(p, tags: tags) {
            blocks.append(parse_textblock(str: p.str, from: starting_from, to: pre_mention))
            blocks.append(.mention(mention))
            starting_from = p.pos
        } else {
            p.pos += 1
        }
    }
    
    return blocks
}

func parse_mention(_ p: Parser, tags: [[String]]) -> Mention? {
    let start = p.pos
    
    if !parse_str(p, "#[") {
        return nil
    }
    
    guard let digit = parse_digit(p) else {
        p.pos = start
        return nil
    }
    
    if !parse_char(p, "]") {
        return nil
    }
    
    var kind: MentionType = .pubkey
    if digit > tags.count - 1 {
        return nil
    }
    
    if tags[digit].count == 0 {
        return nil
    }
    
    switch tags[digit][0] {
    case "e": kind = .event
    case "p": kind = .pubkey
    default: return nil
    }
    
    guard let ref = tag_to_refid(tags[digit]) else {
        return nil
    }
    
    return Mention(index: digit, type: kind, ref: ref)
}

func post_to_event(post: NostrPost, privkey: String, pubkey: String) -> NostrEvent {
    let new_ev = NostrEvent(content: post.content, pubkey: pubkey)
    for id in post.references {
        var tag = [id.key, id.ref_id]
        if let relay_id = id.relay_id {
            tag.append(relay_id)
        }
        new_ev.tags.append(tag)
    }
    new_ev.calculate_id()
    new_ev.sign(privkey: privkey)
    return new_ev
}

