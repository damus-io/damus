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

    mutating func next() -> TagSequence? {
        guard !done else { return nil }

        let tag_seq = TagSequence(note: iter.note, tag: self.iter.tag)

        let ok = ndb_tags_iterate_next(&self.iter)
        done = ok == 0

        return tag_seq
    }

    init(note: UnsafeMutablePointer<ndb_note>) {
        self.iter = ndb_iterator()
        let res = ndb_tags_iterate_start(note, &self.iter)
        self.done = res == 0
    }
}

struct TagsSequence: Sequence {
    let note: UnsafeMutablePointer<ndb_note>

    func makeIterator() -> TagsIterator {
        return .init(note: note)
    }
}
