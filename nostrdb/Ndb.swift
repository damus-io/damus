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

    static var empty: Ndb {
        Ndb(ndb: ndb_t(ndb: nil))
    }

    init?() {
        //try? FileManager.default.removeItem(atPath: Ndb.db_path + "/lock.mdb")
        //try? FileManager.default.removeItem(atPath: Ndb.db_path + "/data.mdb")

        var ndb_p: OpaquePointer? = nil

        let ingest_threads: Int32 = 4
        var mapsize: Int = 1024 * 1024 * 1024 * 32

        let ok = Ndb.db_path.withCString { testdir in
            var ok = false
            while !ok && mapsize > 1024 * 1024 * 700 {
                ok = ndb_init(&ndb_p, testdir, mapsize, ingest_threads) != 0
                if !ok {
                    mapsize /= 2
                }
            }
            return ok
        }

        if !ok {
            return nil
        }

        self.ndb = ndb_t(ndb: ndb_p)
    }

    init(ndb: ndb_t) {
        self.ndb = ndb
    }

    func lookup_note_by_key(_ key: UInt64) -> NdbNote? {
        guard let note_p = ndb_get_note_by_key(ndb.ndb, key, nil) else {
            return nil
        }
        return NdbNote(note: note_p, owned_size: nil)
    }

    func lookup_note(_ id: NoteId) -> NdbNote? {
        id.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> NdbNote? in
            guard let baseAddress = ptr.baseAddress,
                  let note_p = ndb_get_note_by_id(ndb.ndb, baseAddress, nil) else {
                return nil
            }
            return NdbNote(note: note_p, owned_size: nil)
        }
    }

    func lookup_profile(_ pubkey: Pubkey) -> NdbProfileRecord? {
        return pubkey.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> NdbProfileRecord? in
            var size: Int = 0

            guard let baseAddress = ptr.baseAddress,
                  let profile_p = ndb_get_profile_by_pubkey(ndb.ndb, baseAddress, &size)
            else {
                return nil
            }

            do {
                var buf = ByteBuffer(assumingMemoryBound: profile_p, capacity: size)
                let rec: NdbProfileRecord = try getCheckedRoot(byteBuffer: &buf)
                return rec
            } catch {
                // Handle error appropriately
                print("UNUSUAL: \(error)")
                return nil
            }
        }
    }
    func process_event(_ str: String) -> Bool {
        return str.withCString { cstr in
            return ndb_process_event(ndb.ndb, cstr, Int32(str.utf8.count)) != 0
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
