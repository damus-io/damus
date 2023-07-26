//
//  Reply.swift
//  damus
//
//  Created by William Casarin on 2022-05-08.
//

import Foundation

struct ReplyDesc {
    let pubkeys: [Pubkey]
    let others: Int
}

func make_reply_description(_ tags: Tags) -> ReplyDesc {
    var c = 0
    var ns: [Pubkey] = []
    var i = tags.count

    for tag in tags {
        if let pk = Pubkey.from_tag(tag: tag) {
            c += 1
            if ns.count < 2 {
                ns.append(pk)
            }
        }
        i -= 1
    }

    return ReplyDesc(pubkeys: ns, others: c)
}
