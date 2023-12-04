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

        return TagSequence(note: note, tag: self.iter.tag)
    }

    var count: UInt16 {
        return note.note.pointee.tags.count
    }

    init(note: NdbNote) {
        self.iter = ndb_iterator()
        ndb_tags_iterate_start(note.note, &self.iter)
        self.done = false
        self.note = note
    }
}

struct TagsSequence: Encodable, Sequence {
    let note: NdbNote

    var count: UInt16 {
        note.note.pointee.tags.count
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
        return .init(note: .init(note: .allocate(capacity: 1), size: 0, owned: true, key: nil), tag: .allocate(capacity: 1))
    }

    func makeIterator() -> TagsIterator {
        return .init(note: note)
    }
}
