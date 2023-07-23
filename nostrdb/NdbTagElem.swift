//
//  NdbTagElem.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct NdbStrIter: IteratorProtocol {
    typealias Element = CChar

    var ind: Int
    let str: ndb_str
    let tag: NdbTagElem // stored for lifetime reasons

    mutating func next() -> CChar? {
        let c = str.str[ind]
        if (c != 0) {
            ind += 1
            return c
        }

        return nil
    }

    init(tag: NdbTagElem) {
        self.str = ndb_tag_str(tag.note.note, tag.tag, tag.index)
        self.ind = 0
        self.tag = tag
    }
}

struct NdbTagElem: Sequence {
    let note: NdbNote
    let tag: UnsafeMutablePointer<ndb_tag>
    let index: Int32

    init(note: NdbNote, tag: UnsafeMutablePointer<ndb_tag>, index: Int32) {
        self.note = note
        self.tag = tag
        self.index = index
    }

    var is_id: Bool {
        return ndb_tag_str(note.note, tag, index).flag == NDB_PACKED_ID
    }

    var count: Int {
        let r = ndb_tag_str(note.note, tag, index)
        if r.flag == NDB_PACKED_ID {
            return 32
        } else {
            return strlen(r.str)
        }
    }

    func matches_char(_ c: AsciiCharacter) -> Bool {
        return ndb_tag_matches_char(note.note, tag, index, c.cchar) == 1
    }

    func data() -> NdbData {
        let s = ndb_tag_str(note.note, tag, index)
        return NdbData(note: note, str: s)
    }

    func id() -> Data? {
        guard case .id(let id) = self.data() else { return nil }
        return id.id
    }

    func string() -> String {
        switch self.data() {
        case .id(let id):
            return hex_encode(id.id)
        case .str(let s):
            return String(cString: s.str, encoding: .utf8) ?? ""
        }
    }

    func makeIterator() -> NdbStrIter {
        return NdbStrIter(tag: self)
    }
}

