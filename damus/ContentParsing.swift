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
        if note.known_kind == .dm {
            self = .content(note.get_content(keypair), note.tags)
        } else {
            self = .note(note)
        }
    }
}

func interpret_event_refs_ndb(tags: TagsSequence) -> [EventRef] {
    if tags.count == 0 {
        return []
    }
    
    return interp_event_refs_without_mentions_ndb(References<NoteRef>(tags: tags))
}

func interp_event_refs_without_mentions_ndb(_ ev_tags: References<NoteRef>) -> [EventRef] {

    var count = 0
    var evrefs: [EventRef] = []
    var first: Bool = true
    var first_ref: NoteRef? = nil

    for ref in ev_tags {
        if let marker = ref.marker {
            switch marker {
            case .mention:
                evrefs.append(.mention(.noteref(ref)))
            case .reply:
                evrefs.append(.reply(ref))
            case .root:
                evrefs.append(.reply_to_root(ref))
            }
        } else {
            if first {
                first_ref = ref
                evrefs.append(.thread_id(ref))
                first = false
            } else {
                evrefs.append(.reply(ref))
            }
            count += 1
        }
    }

    if let first_ref, count == 1 {
        let r = first_ref
        return [.reply_to_root(r)]
    }

    return evrefs
}

func interp_event_refs_with_mentions_ndb(tags: TagsSequence, mention_indices: Set<Int>) -> [EventRef] {
    var mentions: [EventRef] = []
    var ev_refs: [NoteRef] = []
    var i: Int = 0

    for tag in tags {
        if let note_id = NoteRef.from_tag(tag: tag) {
            if mention_indices.contains(i) {
                mentions.append(.mention(.noteref(note_id, index: i)))
            } else {
                ev_refs.append(note_id)
            }
        }
        i += 1
    }
    
    var replies = interp_event_refs_without_mentions(ev_refs)
    replies.append(contentsOf: mentions)
    return replies
}
