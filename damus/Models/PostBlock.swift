//
//  PostBlock.swift
//  damus
//
//  Created by William Casarin on 2022-05-07.
//

import Foundation

enum PostBlock {
    case text(String)
    case ref(ReferencedId)
    
    var is_text: Bool {
        if case .text = self {
            return true
        }
        return false
    }
    
    var is_ref: Bool {
        if case .ref = self {
            return true
        }
        return false
    }
}

func parse_post_textblock(str: String, from: Int, to: Int) -> PostBlock {
    return .text(String(substring(str, start: from, end: to)))
}
