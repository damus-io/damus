//
//  ThreadReply.swift
//  damus
//
//  Created by William Casarin on 2024-05-09.
//

import Foundation


struct ThreadReply {
    let root: NoteRef
    let reply: NoteRef?
    let mention: Mention<NoteRef>?

    var is_reply_to_root: Bool {
        guard let reply else {
            // if we have no reply and only root then this is reply-to-root,
            // but it should never really be in this form...
            return true
        }

        return root.id == reply.id
    }

    init(root: NoteRef, reply: NoteRef?, mention: Mention<NoteRef>?) {
        self.root = root
        self.reply = reply
        self.mention = mention
    }

    init?(event_refs: [EventRef]) {
        var root: NoteRef? = nil
        var reply: NoteRef? = nil
        var mention: Mention<NoteRef>? = nil

        for evref in event_refs {
            switch evref {
            case .mention(let m):
                mention = m
            case .thread_id(let r):
                root = r
            case .reply(let r):
                reply = r
            case .reply_to_root(let r):
                root = r
                reply = r
            }
        }

        // nip10 threads must have a root
        guard let root else {
            return nil
        }

        self = ThreadReply(root: root, reply: reply, mention: mention)
    }
}
