//
//  NdbTagIterators.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct TagSequence: Sequence {
    let note: NdbNote
    let tag: ndb_tag_ptr

    var count: UInt16 {
        ndb_tag_count(tag.ptr)
    }

    func strings() -> [String] {
        return self.map { $0.string() }
    }

    subscript(index: Int) -> NdbTagElem {
        precondition(index < count, "Index out of bounds")

        return NdbTagElem(note: note, tag: tag, index: Int32(index))
    }

    func makeIterator() -> TagIterator {
        return TagIterator(note: note, tag: tag)
    }
}

struct TagIterator: IteratorProtocol {
    typealias Element = NdbTagElem

    mutating func next() -> NdbTagElem? {
        guard index < ndb_tag_count(tag.ptr) else { return nil }
        let el = NdbTagElem(note: note, tag: tag, index: index)

        index += 1

        return el
    }

    var index: Int32
    let note: NdbNote
    var tag: ndb_tag_ptr

    var count: UInt16 {
        ndb_tag_count(tag.ptr)
    }

    init(note: NdbNote, tag: ndb_tag_ptr) {
        self.note = note
        self.tag = tag
        self.index = 0
    }
}
