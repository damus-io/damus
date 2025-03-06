//
//  NdbBlockIterator.swift
//  damus
//
//  Created by William Casarin on 2024-01-25.
//

import Foundation


struct BlocksIterator: IteratorProtocol {
    typealias Element = NdbBlock

    var done: Bool
    var iter: ndb_block_iterator
    var note: NdbNote

    mutating func next() -> NdbBlock? {
        guard iter.blocks != nil,
              let ptr = ndb_blocks_iterate_next(&iter) else {
            done = true
            return nil
        }

        let block_ptr = ndb_block_ptr(ptr: ptr)
        return NdbBlock(block_ptr)
    }

    init(note: NdbNote, blocks: NdbBlocks) {
        let content = ndb_note_content(note.note.ptr)
        self.iter = ndb_block_iterator(content: content, blocks: nil, block: ndb_block(), p: nil)
        ndb_blocks_iterate_start(content, blocks.as_ptr(), &self.iter)
        self.done = false
        self.note = note
    }
}

struct BlocksSequence: Sequence {
    let blocks: NdbBlocks
    let note: NdbNote

    init(note: NdbNote, blocks: NdbBlocks) {
        self.blocks = blocks
        self.note = note
    }

    func makeIterator() -> BlocksIterator {
        return .init(note: note, blocks: blocks)
    }
    
    func collect() -> [NdbBlock] {
        var xs = [NdbBlock]()
        for x in self {
            xs.append(x)
        }
        return xs
    }
}

