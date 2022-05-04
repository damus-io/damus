//
//  Parser.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import Foundation

func parse_str(_ p: Parser, _ s: String) -> Bool {
    let sub = substring(p.str, start: p.pos, end: p.pos + s.count)
    if sub == s {
        p.pos += s.count
        return true
    }
    return false
}

func parse_char(_ p: Parser, _ c: Character) -> Bool{
    let ind = p.str.index(p.str.startIndex, offsetBy: p.pos)
    
    if p.str[ind] == c {
        p.pos += 1
        return true
    }
    
    return false
}

func parse_digit(_ p: Parser) -> Int? {
    let ind = p.str.index(p.str.startIndex, offsetBy: p.pos)
    
    if let c = p.str[ind].unicodeScalars.first {
        let d = Int(c.value) - 48
        if d >= 0 && d < 10 {
            p.pos += 1
            return Int(d)
        }
    }
    
    return 0
}
