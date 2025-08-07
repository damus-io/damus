//
//  EventRef.swift
//  damus
//
//  Created by William Casarin on 2022-05-08.
//

import Foundation

enum EventRef: Equatable {
    case mention(Mention<NoteRef>)
    case thread_id(NoteRef)
    case reply(NoteRef)
    case reply_to_root(NoteRef)

    var is_mention: NoteRef? {
        if case .mention(let m) = self { return m.ref }
        return nil
    }
    
    var is_direct_reply: NoteRef? {
        switch self {
        case .mention:
            return nil
        case .thread_id:
            return nil
        case .reply(let refid):
            return refid
        case .reply_to_root(let refid):
            return refid
        }
    }
    
    var is_thread_id: NoteRef? {
        switch self {
        case .mention:
            return nil
        case .thread_id(let referencedId):
            return referencedId
        case .reply:
            return nil
        case .reply_to_root(let referencedId):
            return referencedId
        }
    }
    
    var is_reply: NoteRef? {
        switch self {
        case .mention:
            return nil
        case .thread_id:
            return nil
        case .reply(let refid):
            return refid
        case .reply_to_root(let refid):
            return refid
        }
    }
}

func build_mention_indices(_ blocks: BlocksSequence, type: MentionType) -> Set<Int> {
    return blocks.reduce(into: []) { acc, block in
        switch block {
        case .mention:
            return
        case .mention_index(let idx):
            return
        case .text:
            return
        case .hashtag:
            return
        case .url:
            return
        case .invoice:
            return
        }
    }
}

func interp_event_refs_without_mentions(_ refs: [NoteRef]) -> [EventRef] {
    if refs.count == 0 {
        return []
    }

    if refs.count == 1 {
        return [.reply_to_root(refs[0])]
    }
    
    var evrefs: [EventRef] = []
    var first: Bool = true
    for ref in refs {
        if first {
            evrefs.append(.thread_id(ref))
            first = false
        } else {
            evrefs.append(.reply(ref))
        }
    }
    return evrefs
}

func interp_event_refs_with_mentions(tags: Tags) -> [EventRef] {
    var mentions: [EventRef] = []
    var ev_refs: [NoteRef] = []
    var i: Int = 0

    for tag in tags {
        if let ref = NoteRef.from_tag(tag: tag) {
            ev_refs.append(ref)
        }
        i += 1
    }
    
    var replies = interp_event_refs_without_mentions(ev_refs)
    replies.append(contentsOf: mentions)
    return replies
}

func interpret_event_refs(tags: Tags) -> [EventRef] {
    if tags.count == 0 {
        return []
    }
    
    /// build a set of indices for each event mention
    //let mention_indices = build_mention_indices(blocks, type: .e)

    /// simpler case with no mentions
    //if mention_indices.count == 0 {
        //return interp_event_refs_without_mentions_ndb(References<NoteRef>(tags: tags))
    //}

    return interp_event_refs_with_mentions(tags: tags)
}

func ndb_interpret_event_refs(tags: Tags) -> [EventRef] {
    if tags.count == 0 {
        return []
    }
    
    /// build a set of indices for each event mention
    //let mention_indices = build_mention_indices(blocks, type: .e)

    /// simpler case with no mentions
    //if mention_indices.count == 0 {
        //return interp_event_refs_without_mentions_ndb(References<NoteRef>(tags: tags))
    //}

    return interp_event_refs_with_mentions(tags: tags)
}


func event_is_reply(_ refs: [EventRef]) -> Bool {
    return refs.contains { evref in
        return evref.is_reply != nil
    }
}
