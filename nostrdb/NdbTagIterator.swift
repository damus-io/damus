//
//  NdbTagIterators.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct TagSequence: Sequence {
    let note: NdbNote
    let tag: UnsafeMutablePointer<ndb_tag>

    var count: UInt16 {
        tag.pointee.count
    }

    subscript(index: Int) -> NdbTagElem? {
        if index >= tag.pointee.count {
            return nil
        }

        return NdbTagElem(note: note, tag: tag, index: Int32(index))
    }

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

    subscript(index: Int) -> NdbTagElem? {
        if index >= tag.pointee.count {
            return nil
        }

        return NdbTagElem(note: note, tag: tag, index: Int32(index))
    }

    var index: Int32
    let note: NdbNote
    var tag: UnsafeMutablePointer<ndb_tag>

    var count: UInt16 {
        tag.pointee.count
    }

    init(note: NdbNote, tag: UnsafeMutablePointer<ndb_tag>) {
        self.note = note
        self.tag = tag
        self.index = 0
    }
}


func ndb_maybe_pointee<T>(_ p: UnsafeMutablePointer<T>!) -> T? {
    guard p != nil else { return nil }
    return p.pointee
}

