//
//  Ndb.swift
//  damus
//
//  Created by William Casarin on 2023-08-25.
//

import Foundation

class Ndb {
    let ndb: ndb_t

    init?() {
        var ndb_p: OpaquePointer? = nil

        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.absoluteString.replacingOccurrences(of: "file://", with: "")

        let ok = dir!.withCString { testdir in
            return ndb_init(&ndb_p, testdir, 1024 * 1024 * 700, 4) != 0
        }

        if !ok {
            return nil
        }

        self.ndb = ndb_t(ndb: ndb_p)
    }

    func lookup_note(_ id: NoteId) -> NdbNote? {
        id.id.withUnsafeBytes { bs in
            guard let note_p = ndb_get_note_by_id(ndb.ndb, bs) else {
                return nil
            }
            return NdbNote(note: note_p, owned_size: nil)
        }
    }

    func process_events(_ str: String) -> Bool {
        return str.withCString { cstr in
            return ndb_process_events(ndb.ndb, cstr, str.utf8.count) != 0
        }
    }

    deinit {
        ndb_destroy(ndb.ndb)
    }
}
