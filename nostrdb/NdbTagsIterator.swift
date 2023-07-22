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
        guard !done else { return nil }

        let tag_seq = TagSequence(note: note, tag: self.iter.tag)

        let ok = ndb_tags_iterate_next(&self.iter)
        done = ok == 0

        return tag_seq
    }

    var count: UInt16 {
        return iter.tag.pointee.count
    }

    init(note: NdbNote) {
        self.iter = ndb_iterator()
        let res = ndb_tags_iterate_start(note.note, &self.iter)
        self.done = res == 0
        self.note = note
    }
}

struct TagsSequence: Sequence {
    let note: NdbNote

    func makeIterator() -> TagsIterator {
        return .init(note: note)
    }
}
