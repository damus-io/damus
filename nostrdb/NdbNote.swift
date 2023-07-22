//
//  NdbNote.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct NdbNote {
    // we can have owned notes, but we can also have lmdb virtual-memory mapped notes so its optional
    private var owned: Data?
    let note: UnsafeMutablePointer<ndb_note>

    init(note: UnsafeMutablePointer<ndb_note>, data: Data?) {
        self.note = note
        self.owned = data
    }

    var owned_size: Int? {
        return owned?.count
    }

    var content: String {
        String(cString: ndb_note_content(note), encoding: .utf8) ?? ""
    }

    var id: Data {
        Data(buffer: UnsafeBufferPointer(start: ndb_note_id(note), count: 32))
    }

    var pubkey: Data {
        Data(buffer: UnsafeBufferPointer(start: ndb_note_pubkey(note), count: 32))
    }

    func tags() -> TagsSequence {
        return .init(note: note)
    }

    static func owned_from_json(json: String, bufsize: Int = 2 << 18) -> NdbNote? {
        var data = Data(capacity: bufsize)
        guard var json_cstr = json.cString(using: .utf8) else { return nil }

        var note: UnsafeMutablePointer<ndb_note>?

        let len = data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            return ndb_note_from_json(&json_cstr, Int32(json_cstr.count), &note, bytes.baseAddress, Int32(bufsize))
        }

        guard let note else { return nil }

        // Create new Data with just the valid bytes
        let smol_data = Data(bytes: &note.pointee, count: Int(len))
        return NdbNote(note: note, data: smol_data)
    }}
