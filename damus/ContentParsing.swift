//
//  ContentParsing.swift
//  damus
//
//  Created by William Casarin on 2023-07-22.
//

import Foundation

func tag_to_refid_ndb(_ tag: TagSequence) -> ReferencedId? {
    guard let ref_id = tag[1]?.string(),
          let key = tag[0]?.string() else { return nil }

    let relay_id = tag[2]?.string()

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
        
        if let converted = convert_block_ndb(block, tags: note.tags()) {
            out.append(converted)
        }
        
        i += 1
    }
    
    let words = Int(bs.words)
    blocks_free(&bs)
    
    return Blocks(words: words, blocks: out)
}

