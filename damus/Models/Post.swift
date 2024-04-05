//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-05-07.
//

import Foundation

struct NostrPost {
    let kind: NostrKind
    let content: String
    let references: [RefId]
    let tags: [[String]]

    init(content: String, references: [RefId], kind: NostrKind = .text, tags: [[String]] = []) {
        self.content = content
        self.references = references
        self.kind = kind
        self.tags = tags
    }
}

/// This should only be used in tests, we don't use this anymore directly
func parse_note_content(content: NoteContent) -> Blocks?
{
    switch content {
    case .note(let note):
        return parse_post_blocks(content: note.content)
    case .content(let content, _):
        return parse_post_blocks(content: content)
    }
}

/// Return a list of tags
func parse_post_blocks(content: String) -> Blocks? {
    let buf_size = 16000
    var buffer = Data(capacity: buf_size)
    var blocks_ptr = ndb_blocks_ptr()
    var ok = false

    return content.withCString { c_content -> Blocks? in
        buffer.withUnsafeMutableBytes { buf in
            let res = ndb_parse_content(buf, Int32(buf_size), c_content, Int32(content.utf8.count), &blocks_ptr.ptr)
            ok = res != 0
        }

        guard ok else { return nil }

        let words = ndb_blocks_word_count(blocks_ptr.ptr)
        let bs = collect_blocks(ptr: blocks_ptr, content: c_content)
        return Blocks(words: Int(words), blocks: bs)
    }
}


fileprivate func collect_blocks(ptr: ndb_blocks_ptr, content: UnsafePointer<CChar>) -> [Block] {
    var i = ndb_block_iterator()
    var blocks: [Block] = []
    var block_ptr = ndb_block_ptr()

    ndb_blocks_iterate_start(content, ptr.ptr, &i);
    block_ptr.ptr = ndb_blocks_iterate_next(&i)
    while (block_ptr.ptr != nil) {
        // tags are only used for indexed mentions which aren't used in
        // posts anymore, so to simplify the API let's set this to nil
        if let block = Block(block: block_ptr, tags: nil) {
            blocks.append(block);
        }
        block_ptr.ptr = ndb_blocks_iterate_next(&i)
    }

    return blocks
}
