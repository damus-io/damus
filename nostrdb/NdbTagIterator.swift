//
//  NdbTagIterators.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct TagSequence: Sequence {
    let note: UnsafeMutablePointer<ndb_note>
    let tag: UnsafeMutablePointer<ndb_tag>

    func makeIterator() -> TagIterator {
        return TagIterator(note: note, tag: tag)
    }
}

struct TagIterator: IteratorProtocol {
    typealias Element = NdbTagElem

    mutating func next() -> NdbTagElem? {
        guard index < tag.pointee.count else { return nil }
        let el = NdbTagElem(note: note, tag: tag, index: index)

        index += 1

        return el
    }

    var index: Int32
    let note: UnsafeMutablePointer<ndb_note>
    var tag: UnsafeMutablePointer<ndb_tag>

    init(note: UnsafeMutablePointer<ndb_note>, tag: UnsafeMutablePointer<ndb_tag>) {
        self.note = note
        self.tag = tag
        self.index = 0
    }
}


func ndb_maybe_pointee<T>(_ p: UnsafeMutablePointer<T>!) -> T? {
    guard p != nil else { return nil }
    return p.pointee
}

