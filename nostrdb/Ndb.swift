//
//  Ndb.swift
//  damus
//
//  Created by William Casarin on 2023-08-25.
//

import Foundation

class Ndb {
    let ndb: ndb_t

    static var db_path: String {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.absoluteString.replacingOccurrences(of: "file://", with: ""))!
    }

    init?() {
        var ndb_p: OpaquePointer? = nil

        let ok = Ndb.db_path.withCString { testdir in
            return ndb_init(&ndb_p, testdir, 1024 * 1024 * 1024 * 32, 4) != 0
        }

        if !ok {
            return nil
        }

        self.ndb = ndb_t(ndb: ndb_p)
    }

    func lookup_note(_ id: NoteId) -> NdbNote? {
        id.id.withUnsafeBytes { bs in
            guard let note_p = ndb_get_note_by_id(ndb.ndb, bs, nil) else {
                return nil
            }
            return NdbNote(note: note_p, owned_size: nil)
        }
    }

    func lookup_profile(_ pubkey: Pubkey) -> NdbProfile? {
        return pubkey.id.withUnsafeBytes { pk_bytes in
            var size: Int = 0
            guard let profile_p = ndb_get_profile_by_pubkey(ndb.ndb, pk_bytes, &size) else {
                return nil
            }

            return NdbProfile(.init(memory: profile_p, count: size), o: 0)
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
