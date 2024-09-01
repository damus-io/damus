//
//  ContentParsing.swift
//  damus
//
//  Created by William Casarin on 2023-07-22.
//

import Foundation

enum NoteContent {
    case note(NostrEvent)
    case content(String, TagsSequence?)

    init(note: NostrEvent, keypair: Keypair) {
        if note.known_kind == .dm || note.known_kind == .highlight {
            self = .content(note.get_content(keypair), note.tags)
        } else {
            self = .note(note)
        }
    }
}

func parsed_blocks_finish(bs: inout note_blocks, tags: TagsSequence?) -> Blocks {
    var out: [Block] = []

    var i = 0
    while (i < bs.num_blocks) {
        let block = bs.blocks[i]

        if let converted = Block(block, tags: tags) {
            out.append(converted)
        }

        i += 1
    }

    let words = Int(bs.words)
    blocks_free(&bs)

    return Blocks(words: words, blocks: out)

}

func parse_note_content(content: NoteContent) -> Blocks {
    var bs = note_blocks()
    bs.num_blocks = 0;
    
    blocks_init(&bs)

    switch content {
    case .content(let s, let tags):
        return s.withCString { cptr in
            damus_parse_content(&bs, cptr)
            return parsed_blocks_finish(bs: &bs, tags: tags)
        }
    case .note(let note):
        damus_parse_content(&bs, note.content_raw)
        return parsed_blocks_finish(bs: &bs, tags: note.tags)
    }
}

func interpret_event_refs(tags: TagsSequence) -> ThreadReply? {
    // migration is long over, lets just do this to fix tests
    return interpret_event_refs_ndb(tags: tags)
}

func interpret_event_refs_ndb(tags: TagsSequence) -> ThreadReply? {
    if tags.count == 0 {
        return nil
    }

    return interp_event_refs_without_mentions_ndb(References<NoteRef>(tags: tags))
}

func interp_event_refs_without_mentions_ndb(_ ev_tags: References<NoteRef>) -> ThreadReply? {
    var first: Bool = true
    var root_id: NoteRef? = nil
    var reply_id: NoteRef? = nil
    var mention: NoteRef? = nil
    var any_marker: Bool = false

    for ref in ev_tags {
        if let marker = ref.marker {
            any_marker = true
            switch marker {
            case .root: root_id = ref
            case .reply: reply_id = ref
            case .mention: mention = ref
            }
        // deprecated form, only activate if we don't have any markers set
        } else if !any_marker {
            if first {
                root_id = ref
                first = false
            } else {
                reply_id = ref
            }
        }
    }

    // If either reply or root_id is blank while the other is not, then this is
    // considered reply-to-root. We should always have a root and reply tag, if they
    // are equal this is reply-to-root
    if reply_id == nil && root_id != nil {
        reply_id = root_id
    } else if root_id == nil && reply_id != nil {
        root_id = reply_id
    }

    guard let reply_id, let root_id else {
        return nil
    }

    return ThreadReply(root: root_id, reply: reply_id, mention: mention.map { m in .noteref(m) })
}
