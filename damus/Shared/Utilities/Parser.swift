//
//  Parser.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import Foundation

class Parser {
    var pos: Int
    var str: String
    
    init(pos: Int, str: String) {
        self.pos = pos
        self.str = str
    }
}

func consume_until(_ p: Parser, match: (Character) -> Bool, end_ok: Bool = false) -> Bool {
    let sub = substring(p.str, start: p.pos, end: p.str.count)
    let start = p.pos
    
    for c in sub {
        if match(c) {
            return true
        }
        p.pos += 1
    }
    
    if end_ok {
        return true
    }
    
    p.pos = start
    return false
}

func substring(_ s: String, start: Int, end: Int) -> Substring {
    let ind = s.index(s.startIndex, offsetBy: start)
    let end = s.index(s.startIndex, offsetBy: end)
    return s[ind..<end]
}


func parse_str(_ p: Parser, _ s: String) -> Bool {
    if p.pos + s.count > p.str.count {
        return false
    }
    let sub = substring(p.str, start: p.pos, end: p.pos + s.count)
    if sub == s {
        p.pos += s.count
        return true
    }
    return false
}

func parse_char(_ p: Parser, _ c: Character) -> Bool {
    if p.pos >= p.str.count {
        return false
    }
    
    let ind = p.str.index(p.str.startIndex, offsetBy: p.pos)
    
    if p.str[ind] == c {
        p.pos += 1
        return true
    }
    
    return false
}

func parse_hex_char(_ p: Parser) -> Character? {
    let ind = p.str.index(p.str.startIndex, offsetBy: p.pos)
    
    // Check that we're within the bounds of p.str's length
    if p.pos >= p.str.count {
        return nil
    }

    
    if let c = p.str[ind].unicodeScalars.first {
        // hex chars
        let d = c.value
        if (d >= 48 && d <= 57) || (d >= 97 && d <= 102) || (d >= 65 && d <= 70) {
            p.pos += 1
            return p.str[ind]
        }
    }
    
    return nil
}
