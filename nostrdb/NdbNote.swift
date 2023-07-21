//
//  NdbNote.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct NdbNote {
    private var owned: Data?
    let note: UnsafeMutablePointer<ndb_note>

    init(notePointer: UnsafeMutablePointer<ndb_note>, data: Data?) {
        self.note = notePointer
        self.owned = data
    }

    var id: Data {
        Data(buffer: UnsafeBufferPointer(start: ndb_note_id(note), count: 32))
    }

    func tags() -> TagsSequence {
        return .init(note: note)
    }

    static func owned_from_json(json: String, bufsize: Int = 2 << 18) -> NdbNote? {
        var data = Data(capacity: bufsize)
        guard var json_cstr = json.cString(using: .utf8) else { return nil }

        var note: UnsafeMutablePointer<ndb_note>?

        let len = data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) -> Int in
            return Int(ndb_note_from_json(&json_cstr, Int32(json_cstr.count), &note, bytes.baseAddress, Int32(bufsize)))
        }

        guard let note else { return nil }

        // Create new Data with just the valid bytes
        let validData = Data(bytes: &note.pointee, count: len)
        return NdbNote(notePointer: note, data: validData)
    }}
