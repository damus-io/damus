//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-05-07.
//

import Foundation

struct NostrPost {
    let kind: NostrKind
    let content: String
    let tags: [[String]]

    init(content: String, kind: NostrKind = .text, tags: [[String]] = []) {
        self.content = content
        self.kind = kind
        self.tags = tags
    }
}


/// Return a list of tags
func parse_post_blocks(content: String) -> [Block] {
    return parse_note_content(content: .content(content, nil)).blocks
}

