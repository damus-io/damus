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
}

struct Mention {
    let index: Int
    let kind: MentionType
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

struct ParsedMentions {
    let blocks: [Block]
}

class Parser {
    var pos: Int
    var str: String
    
    init(pos: Int, str: String) {
        self.pos = pos
        self.str = str
    }
}

func consume_until(_ p: Parser, match: Character) -> Bool {
    var i: Int = 0
    let sub = substring(p.str, start: p.pos, end: p.str.count)
    for c in sub {
        if c == match {
            p.pos += i
            return true
        }
        i += 1
    }
    
    return false
}

func substring(_ s: String, start: Int, end: Int) -> Substring {
    let ind = s.index(s.startIndex, offsetBy: start)
    let end = s.index(s.startIndex, offsetBy: end)
    return s[ind..<end]
}

func parse_textblock(str: String, from: Int, to: Int) -> Block {
    return .text(String(substring(str, start: from, end: to)))
}

func parse_mentions(content: String, tags: [[String]]) -> [Block] {
    let p = Parser(pos: 0, str: content)
    var blocks: [Block] = []
    var starting_from: Int = 0
    
    while p.pos < content.count {
        if (!consume_until(p, match: "#")) {
            blocks.append(parse_textblock(str: p.str, from: starting_from, to: p.str.count))
            return blocks
        }
        
        let pre_mention = p.pos
        if let mention = parse_mention(p, tags: tags) {
            blocks.append(parse_textblock(str: p.str, from: starting_from, to: pre_mention))
            blocks.append(.mention(mention))
            starting_from = p.pos
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
    
    return Mention(index: digit, kind: kind)
}

