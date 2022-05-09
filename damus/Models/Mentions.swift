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

func find_tag_ref(type: String, id: String, tags: [[String]]) -> Int? {
    var i: Int = 0
    for tag in tags {
        if tag.count >= 2 {
            if tag[0] == type && tag[1] == id {
                return i
            }
        }
        i += 1
    }
    
    return nil
}

struct PostTags {
    let blocks: [Block]
    let tags: [[String]]
}

func parse_mention_type(_ c: String) -> MentionType? {
    if c == "e" {
        return .event
    } else if c == "p" {
        return .pubkey
    }
    
    return nil
}

/// Convert
func make_post_tags(post_blocks: [PostBlock], tags: [[String]]) -> PostTags {
    var new_tags = tags
    var blocks: [Block] = []
    
    for post_block in post_blocks {
        switch post_block {
        case .ref(let ref):
            guard let mention_type = parse_mention_type(ref.key) else {
                continue
            }
            if let ind = find_tag_ref(type: ref.key, id: ref.ref_id, tags: tags) {
                let mention = Mention(index: ind, type: mention_type, ref: ref)
                let block = Block.mention(mention)
                blocks.append(block)
            } else {
                let ind = new_tags.count
                new_tags.append(refid_to_tag(ref))
                let mention = Mention(index: ind, type: mention_type, ref: ref)
                let block = Block.mention(mention)
                blocks.append(block)
            }
        case .text(let txt):
            blocks.append(Block.text(txt))
        }
    }
    
    return PostTags(blocks: blocks, tags: new_tags)
}

func post_to_event(post: NostrPost, privkey: String, pubkey: String) -> NostrEvent {
    let tags = post.references.map(refid_to_tag)
    let post_blocks = parse_post_blocks(content: post.content)
    let post_tags = make_post_tags(post_blocks: post_blocks, tags: tags)
    let content = render_blocks(blocks: post_tags.blocks)
    let new_ev = NostrEvent(content: content, pubkey: pubkey, kind: 1, tags: post_tags.tags)
    new_ev.calculate_id()
    new_ev.sign(privkey: privkey)
    return new_ev
}

