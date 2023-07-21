//
//  NdbTagElem.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct NdbTagElem {
    private let note: UnsafeMutablePointer<ndb_note>
    private let tag: UnsafeMutablePointer<ndb_tag>
    let index: Int32

    init(note: UnsafeMutablePointer<ndb_note>, tag: UnsafeMutablePointer<ndb_tag>, index: Int32) {
        self.note = note
        self.tag = tag
        self.index = index
    }

    func matches_char(c: AsciiCharacter) -> Bool {
        return ndb_tag_matches_char(note, tag, index, c.cchar) == 1
    }

    func string() -> String {
        return String(cString: ndb_tag_str(note, tag, index), encoding: .utf8) ?? ""
    }
}

