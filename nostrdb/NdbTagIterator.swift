//
//  NdbTagIterators.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct TagSequence: Sequence, IteratorProtocol {
    let note: NdbNote
    let tag: UnsafeMutablePointer<ndb_tag>
    var index: Int32

    var count: UInt16 {
        tag.pointee.count
    }

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
}

func ndb_maybe_pointee<T>(_ p: UnsafeMutablePointer<T>!) -> T? {
    guard p != nil else { return nil }
    return p.pointee
}

