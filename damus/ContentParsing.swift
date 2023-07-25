//
//  ContentParsing.swift
//  damus
//
//  Created by William Casarin on 2023-07-22.
//

import Foundation

func tag_to_refid_ndb(_ tag: TagSequence) -> ReferencedId? {
    guard tag.count >= 2 else { return nil }

    let key = tag[0].string()
    let ref_id = tag[1].string()

    var relay_id: String? = nil
    if tag.count >= 3 {
        relay_id = tag[2].string()
    }

    return ReferencedId(ref_id: ref_id, relay_id: relay_id, key: key)
}

func convert_mention_index_block_ndb(ind: Int, tags: TagsSequence) -> Block? {
    if ind < 0 || (ind + 1 > tags.count) || tags[ind]!.count < 2 {
        return .text("#[\(ind)]")
    }
        
    guard let tag = tags[ind], let fst = tag.first(where: { _ in true }) else {
        return nil
    }

    guard let mention_type = parse_mention_type_ndb(fst) else {
        return .text("#[\(ind)]")
    }
    
    guard let ref = tag_to_refid_ndb(tag) else {
        return .text("#[\(ind)]")
    }
    
    return .mention(Mention(index: ind, type: mention_type, ref: ref))
}


func convert_block_ndb(_ b: block_t, tags: TagsSequence) -> Block? {
    if b.type == BLOCK_MENTION_INDEX {
        return convert_mention_index_block_ndb(ind: Int(b.block.mention_index), tags: tags)
    }

    return convert_block(b, tags: [])
}


func parse_note_content_ndb(note: NdbNote) -> Blocks {
    var out: [Block] = []
    
    var bs = note_blocks()
    bs.num_blocks = 0;
    
    blocks_init(&bs)
    
    damus_parse_content(&bs, note.content_raw)

    var i = 0
    while (i < bs.num_blocks) {
        let block = bs.blocks[i]
        
        if let converted = convert_block_ndb(block, tags: note.tags) {
            out.append(converted)
        }
        
        i += 1
    }
    
    let words = Int(bs.words)
    blocks_free(&bs)
    
    return Blocks(words: words, blocks: out)
}

func interpret_event_refs_ndb(blocks: [Block], tags: TagsSequence) -> [EventRef] {
    if tags.count == 0 {
        return []
    }
    
    /// build a set of indices for each event mention
    let mention_indices = build_mention_indices(blocks, type: .event)
    
    /// simpler case with no mentions
    if mention_indices.count == 0 {
        let ev_refs = References.ids(tags: tags)
        return interp_event_refs_without_mentions_ndb(ev_refs)
    }
    
    return interp_event_refs_with_mentions_ndb(tags: tags, mention_indices: mention_indices)
}

func interp_event_refs_without_mentions_ndb(_ ev_tags: LazyFilterSequence<References>) -> [EventRef] {

    var count = 0
    var evrefs: [EventRef] = []
    var first: Bool = true
    var first_ref: Reference? = nil

    for ref in ev_tags {
        if first {
            first_ref = ref
            evrefs.append(.thread_id(ref.to_referenced_id()))
            first = false
        } else {

            evrefs.append(.reply(ref.to_referenced_id()))
        }
        count += 1
    }

    if let first_ref, count == 1 {
        let r = first_ref.to_referenced_id()
        return [.reply_to_root(r)]
    }

    return evrefs
}

func interp_event_refs_with_mentions_ndb(tags: TagsSequence, mention_indices: Set<Int>) -> [EventRef] {
    var mentions: [EventRef] = []
    var ev_refs: [ReferencedId] = []
    var i: Int = 0
    
    for tag in tags {
        if tag.count >= 2,
           tag[0].matches_char("e"),
           let ref = tag_to_refid_ndb(tag)
        {
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
