//
//  NdbTagsIterator.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct TagsIterator: IteratorProtocol {
    typealias Element = TagSequence

    var done: Bool
    var iter: ndb_iterator
    var note: NdbNote

    mutating func next() -> TagSequence? {
        guard ndb_tags_iterate_next(&self.iter) == 1 else {
            done = true
            return nil
        }

        let tag_ptr = ndb_tag_ptr(ptr: self.iter.tag)
        return TagSequence(note: note, tag: tag_ptr)
    }

    init(note: NdbNote) {
        self.iter = ndb_iterator()
        ndb_tags_iterate_start(note.note.ptr, &self.iter)
        self.done = false
        self.note = note
    }
}

struct TagsSequence: Encodable, Sequence {
    let note: NdbNote

    var count: UInt16 {
        let tags_ptr = ndb_note_tags(note.note.ptr)
        return ndb_tags_count(tags_ptr)
    }

    func strings() -> [[String]] {
        return self.map { tag in
            tag.map { t in t.string() }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        
        // Iterate and create the [[String]] for encoding
        for tag in self {
            try container.encode(tag.map { $0.string() })
        }
    }

    // no O(1) indexing on top-level tag lists unfortunately :(
    // bit it's very fast to iterate over each tag since the number of tags
    // are stored and the elements are fixed size.
    subscript(index: Int) -> Iterator.Element {
        var i = 0
        for element in self {
            if i == index {
                return element
            }
            i += 1
        }
        precondition(false, "sequence subscript oob")
        // it seems like the compiler needs this or it gets bitchy
        let nil_ptr = OpaquePointer(bitPattern: 0)
        return .init(note: .init(note: .init(ptr: nil_ptr), size: 0, owned: true, key: nil), tag: .init(ptr: nil_ptr))
    }

    func makeIterator() -> TagsIterator {
        return .init(note: note)
    }
}
