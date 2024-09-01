//
//  CommentItem.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-08-14.
//

import Foundation

struct CommentItem: TagConvertible {
    static let TAG_KEY: String = "comment"
    let content: String
    var tag: [String] {
        return [Self.TAG_KEY, content]
    }
    
    static func from_tag(tag: TagSequence) -> CommentItem? {
        guard tag.count == 2 else { return nil }
        guard tag[0].string() == Self.TAG_KEY else { return nil }
        
        return CommentItem(content: tag[1].string())
    }
}
