//
//  ThreadReply.swift
//  damus
//
//  Created by William Casarin on 2024-05-09.
//

import Foundation


struct ThreadReply {
    let root: NoteRef
    let reply: NoteRef
    let mention: Mention<NoteRef>?

    var is_reply_to_root: Bool {
        return root.id == reply.id
    }

    init(root: NoteRef, reply: NoteRef, mention: Mention<NoteRef>?) {
        self.root = root
        self.reply = reply
        self.mention = mention
    }

    init?(tags: TagsSequence) {
        guard let tr = interpret_event_refs_ndb(tags: tags) else {
            return nil
        }
        self = tr
    }
}
