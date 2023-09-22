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

func make_reply_description(_ event: NostrEvent, replying_to: NostrEvent?) -> ReplyDesc {
    var c = 0
    var ns: [Pubkey] = []
    var i = event.tags.count

    if let replying_to {
        ns.append(replying_to.pubkey)
    }

    for tag in event.tags {
        if let pk = Pubkey.from_tag(tag: tag) {
            c += 1
            if ns.count < 2 {
                if let replying_to, pk == replying_to.pubkey {
                    continue
                } else {
                    ns.append(pk)
                }
            }
        }
        i -= 1
    }

    return ReplyDesc(pubkeys: ns, others: c)
}
