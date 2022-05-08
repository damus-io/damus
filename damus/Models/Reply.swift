//
//  Reply.swift
//  damus
//
//  Created by William Casarin on 2022-05-08.
//

import Foundation

struct ReplyDesc {
    let pubkeys: [String]
    let others: Int
}

func make_reply_description(_ tags: [[String]]) -> ReplyDesc {
    var c = 0
    var ns: [String] = []
    var i = tags.count - 1
        
    while i >= 0 {
        let tag = tags[i]
        if tag.count >= 2 && tag[0] == "p" {
            c += 1
            if ns.count < 2 {
                ns.append(tag[1])
            }
        }
        i -= 1
    }
        
    return ReplyDesc(pubkeys: ns, others: c)
}
