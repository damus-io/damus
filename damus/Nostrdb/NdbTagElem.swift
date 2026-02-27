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
        self.str = ndb_tag_str(tag.note.note.ptr, tag.tag.ptr, tag.index)
        self.ind = 0
        self.tag = tag
    }
}

struct NdbTagElem: Sequence, Hashable, Equatable {
    let note: NdbNote
    let tag: ndb_tag_ptr
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

    init(note: NdbNote, tag: ndb_tag_ptr, index: Int32) {
        self.note = note
        self.tag = tag
        self.index = index
        self.str = ndb_tag_str(note.note.ptr, tag.ptr, index)
    }

    var is_id: Bool {
        return str.flag == NDB_PACKED_ID
    }

    var isEmpty: Bool {
        if str.flag == NDB_PACKED_ID {
            return false
        }
        return str.str[0] == 0
    }

    var count: Int {
        if str.flag == NDB_PACKED_ID {
            return 32
        } else {
            return strlen(str.str)
        }
    }

    var single_char: AsciiCharacter? {
        let c = str.str[0]
        guard c != 0 && str.str[1] == 0 else { return nil }
        return AsciiCharacter(c)
    }

    func matches_char(_ c: AsciiCharacter) -> Bool {
        return str.str[0] == c.cchar && str.str[1] == 0
    }

    func matches_id(_ d: Data) -> Bool {
        if str.flag == NDB_PACKED_ID, d.count == 32 {
            return memcmp(d.bytes, str.id, 32) == 0
        }
        return false
    }

    func matches_str(_ s: String, tag_len: Int? = nil) -> Bool {
        if str.flag == NDB_PACKED_ID,
           s.utf8.count == 64,
           var decoded = hex_decode(s), decoded.count == 32
        {
            return memcmp(&decoded, str.id, 32) == 0
        }

        // Ensure the Swift string's utf8 count matches the C string's length.
        guard (tag_len ?? strlen(str.str)) == s.utf8.count else {
            return false
        }

        // Compare directly using the utf8 view.
        return s.utf8.withContiguousStorageIfAvailable { buffer in
            memcmp(buffer.baseAddress, str.str, buffer.count) == 0
        } ?? false
    }

    func data() -> NdbData {
        return NdbData(note: note, str: self.str)
    }

    func id() -> Data? {
        guard case .id(let id) = self.data() else { return nil }
        return id.id
    }

    func u64() -> UInt64? {
        switch self.data() {
        case .id:
            return nil
        case .str(let str):
            var end_ptr = UnsafeMutablePointer<CChar>(nil as OpaquePointer?)
            let res = strtoull(str.str, &end_ptr, 10)

            if end_ptr?.pointee == 0 {
                return res
            } else {
                return nil
            }
        }
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

