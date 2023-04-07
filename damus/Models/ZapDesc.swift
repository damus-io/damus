//
//  ZapDescription.swift
//  damus
//
//  Created by eric on 4/5/23.
//

import Foundation

struct ZapDesc {
    let pubkeys: [String]
    let others: Int
}

func make_zap_description(_ tags: [[String]]) -> ZapDesc {
    var c = 0
    var ns: [String] = []
    var i = tags.count - 1
        
    while i >= 0 {
        let tag = tags[i]
        if tag.count >= 2 && tag[0] == "zap" {
            c += 1
            if ns.count < 2 {
                ns.append(tag[1])
            }
        }
        i -= 1
    }
        
    return ReplyDesc(pubkeys: ns, others: c)
}
