//
//  EventRef.swift
//  damus
//
//  Created by William Casarin on 2022-05-08.
//

import Foundation

enum EventRef {
    case mention(Mention)
    case thread_id(ReferencedId)
    case reply(ReferencedId)
    case reply_to_root(ReferencedId)
    
    var is_mention: Mention? {
        if case .mention(let m) = self {
            return m
        }
        return nil
    }
    
    var is_direct_reply: ReferencedId? {
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
    
    var is_thread_id: ReferencedId? {
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
    
    var is_reply: ReferencedId? {
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

func has_any_e_refs(_ tags: [[String]]) -> Bool {
    for tag in tags {
        if tag.count >= 2 && tag[0] == "e" {
            return true
        }
    }
    return false
}

func build_mention_indices(_ blocks: [Block], type: MentionType) -> Set<Int> {
    return blocks.reduce(into: []) { acc, block in
        switch block {
        case .mention(let m):
            if m.type == type {
                acc.insert(m.index)
            }
        case .text:
            return
        case .hashtag:
            return
        }
    }
}

func interp_event_refs_without_mentions(_ refs: [ReferencedId]) -> [EventRef] {
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

func interp_event_refs_with_mentions(tags: [[String]], mention_indices: Set<Int>) -> [EventRef] {
    var mentions: [EventRef] = []
    var ev_refs: [ReferencedId] = []
    var i: Int = 0
    
    for tag in tags {
        if tag.count >= 2 && tag[0] == "e" {
            let ref = tag_to_refid(tag)!
            if mention_indices.contains(i) {
                let mention = Mention(index: i, type: .event, ref: ref)
                mentions.append(.mention(mention))
            } else {
                ev_refs.append(ref)
            }
        }
        i += 1
    }
    
    var replies = interp_event_refs_without_mentions(ev_refs)
    replies.append(contentsOf: mentions)
    return replies
}

func interpret_event_refs(blocks: [Block], tags: [[String]]) -> [EventRef] {
    if tags.count == 0 {
        return []
    }
    
    /// build a set of indices for each event mention
    let mention_indices = build_mention_indices(blocks, type: .event)
    
    /// simpler case with no mentions
    if mention_indices.count == 0 {
        let ev_refs = get_referenced_ids(tags: tags, key: "e")
        return interp_event_refs_without_mentions(ev_refs)
    }
    
    return interp_event_refs_with_mentions(tags: tags, mention_indices: mention_indices)
}


func event_is_reply(_ ev: NostrEvent) -> Bool {
    return ev.event_refs.contains { evref in
        return evref.is_reply != nil
    }
}

