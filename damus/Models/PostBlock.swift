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
    case hashtag(String)
    
    var is_text: String? {
        if case .text(let txt) = self {
            return txt
        }
        return nil
    }
    
    var is_hashtag: String? {
        if case .hashtag(let ht) = self {
            return ht
        }
        return nil
    }
    
    var is_ref: ReferencedId? {
        if case .ref(let ref) = self {
            return ref
        }
        return nil
    }
}

func parse_post_textblock(str: String, from: Int, to: Int) -> PostBlock {
    return .text(String(substring(str, start: from, end: to)))
}
