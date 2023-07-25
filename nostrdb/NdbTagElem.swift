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

struct NdbTagElem: Sequence, Hashable {

    let note: NdbNote
    let tag: UnsafeMutablePointer<ndb_tag>
    let index: Int32
    let str: ndb_str

    func hash(into hasher: inout Hasher) {
        if str.flag == NDB_PACKED_ID {
            hasher.combine(bytes: UnsafeRawBufferPointer(start: str.id, count: 32))
        } else {
            hasher.combine(bytes: UnsafeRawBufferPointer(start: str.str, count: strlen(str.str)))
        }
    }

    static func == (lhs: NdbTagElem, rhs: NdbTagElem) -> Bool {
        if lhs.str.flag == NDB_PACKED_ID && rhs.str.flag == NDB_PACKED_ID {
            return memcmp(lhs.str.id, rhs.str.id, 32) == 0
        } else if lhs.str.flag == NDB_PACKED_ID || rhs.str.flag == NDB_PACKED_ID {
            return false
        }

        let l = strlen(lhs.str.str)
        let r = strlen(rhs.str.str)
        if l != r { return false }

        return memcmp(lhs.str.str, rhs.str.str, r) == 0
    }

    init(note: NdbNote, tag: UnsafeMutablePointer<ndb_tag>, index: Int32) {
        self.note = note
        self.tag = tag
        self.index = index
        self.str = ndb_tag_str(note.note, tag, index)
    }

    var is_id: Bool {
        return str.flag == NDB_PACKED_ID
    }

    var count: Int {
        if str.flag == NDB_PACKED_ID {
            return 32
        } else {
            return strlen(str.str)
        }
    }

    func matches_char(_ c: AsciiCharacter) -> Bool {
        return str.str[0] == c.cchar && str.str[1] == 0
    }

    func matches_str(_ s: String) -> Bool {
        if str.flag == NDB_PACKED_ID,
           s.utf8.count == 64,
           var decoded = hex_decode(s), decoded.count == 32
        {
            return memcmp(&decoded, str.id, 32) == 0
        }

        let len = strlen(str.str)
        guard len == s.utf8.count else { return false }
        return s.withCString { cstr in memcmp(str.str, cstr, len) == 0 }
    }

    var ndbstr: ndb_str {
        return ndb_tag_str(note.note, tag, index)
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

