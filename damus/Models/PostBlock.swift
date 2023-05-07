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
}

func parse_post_textblock(str: String, from: Int, to: Int) -> PostBlock {
    return .text(String(substring(str, start: from, end: to)))
}
