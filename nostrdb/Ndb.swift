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
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.absoluteString
        return remove_file_prefix(path!)
    }

    static var empty: Ndb {
        Ndb(ndb: ndb_t(ndb: nil))
    }

    init?(path: String? = nil) {
        //try? FileManager.default.removeItem(atPath: Ndb.db_path + "/lock.mdb")
        //try? FileManager.default.removeItem(atPath: Ndb.db_path + "/data.mdb")

        var ndb_p: OpaquePointer? = nil

        let ingest_threads: Int32 = 4
        var mapsize: Int = 1024 * 1024 * 1024 * 32

        let path = path.map(remove_file_prefix) ?? Ndb.db_path

        let ok = path.withCString { testdir in
            var ok = false
            while !ok && mapsize > 1024 * 1024 * 700 {
                ok = ndb_init(&ndb_p, testdir, mapsize, ingest_threads, 0) != 0
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

    func lookup_note_by_key_with_txn<Y>(_ key: NoteKey, txn: NdbTxn<Y>) -> NdbNote? {
        guard let note_p = ndb_get_note_by_key(&txn.txn, key, nil) else {
            return nil
        }
        return NdbNote(note: note_p, owned_size: nil, key: key)
    }

    func lookup_note_by_key(_ key: NoteKey) -> NdbTxn<NdbNote?> {
        return NdbTxn(ndb: self) { txn in
            lookup_note_by_key_with_txn(key, txn: txn)
        }
    }

    private func lookup_profile_by_key_inner<Y>(_ key: ProfileKey, txn: NdbTxn<Y>) -> ProfileRecord? {
        var size: Int = 0
        guard let profile_p = ndb_get_profile_by_key(&txn.txn, key, &size) else {
            return nil
        }

        return profile_flatbuf_to_record(ptr: profile_p, size: size, key: key)
    }

    private func profile_flatbuf_to_record(ptr: UnsafeMutableRawPointer, size: Int, key: UInt64) -> ProfileRecord? {
        do {
            var buf = ByteBuffer(assumingMemoryBound: ptr, capacity: size)
            let rec: NdbProfileRecord = try getDebugCheckedRoot(byteBuffer: &buf)
            return ProfileRecord(data: rec, key: key)
        } catch {
            // Handle error appropriately
            print("UNUSUAL: \(error)")
            return nil
        }
    }

    private func lookup_note_with_txn_inner<Y>(id: NoteId, txn: NdbTxn<Y>) -> NdbNote? {
        return id.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> NdbNote? in
            var key: UInt64 = 0
            guard let baseAddress = ptr.baseAddress,
                  let note_p = ndb_get_note_by_id(&txn.txn, baseAddress, nil, &key) else {
                return nil
            }
            return NdbNote(note: note_p, owned_size: nil, key: key)
        }
    }

    private func lookup_profile_with_txn_inner<Y>(pubkey: Pubkey, txn: NdbTxn<Y>) -> ProfileRecord? {
        return pubkey.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> ProfileRecord? in
            var size: Int = 0
            var key: UInt64 = 0

            guard let baseAddress = ptr.baseAddress,
                  let profile_p = ndb_get_profile_by_pubkey(&txn.txn, baseAddress, &size, &key)
            else {
                return nil
            }

            return profile_flatbuf_to_record(ptr: profile_p, size: size, key: key)
        }
    }

    func lookup_profile_by_key_with_txn<Y>(key: ProfileKey, txn: NdbTxn<Y>) -> ProfileRecord? {
        lookup_profile_by_key_inner(key, txn: txn)
    }

    func lookup_profile_by_key(key: ProfileKey) -> NdbTxn<ProfileRecord?> {
        return NdbTxn(ndb: self) { txn in
            lookup_profile_by_key_inner(key, txn: txn)
        }
    }

    func lookup_note_with_txn<Y>(id: NoteId, txn: NdbTxn<Y>) -> NdbNote? {
        lookup_note_with_txn_inner(id: id, txn: txn)
    }

    func lookup_profile_key(_ pubkey: Pubkey) -> ProfileKey? {
        return NdbTxn(ndb: self) { txn in
            lookup_profile_key_with_txn(pubkey, txn: txn)
        }.value
    }

    func lookup_profile_key_with_txn<Y>(_ pubkey: Pubkey, txn: NdbTxn<Y>) -> ProfileKey? {
        return pubkey.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> NoteKey? in
            guard let p = ptr.baseAddress else { return nil }
            let r = ndb_get_profilekey_by_pubkey(&txn.txn, p)
            if r == 0 {
                return nil
            }
            return r
        }
    }

    func lookup_note_key_with_txn<Y>(_ id: NoteId, txn: NdbTxn<Y>) -> NoteKey? {
        return id.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> NoteKey? in
            guard let p = ptr.baseAddress else {
                return nil
            }
            let r = ndb_get_notekey_by_id(&txn.txn, p)
            if r == 0 {
                return nil
            }
            return r
        }
    }

    func lookup_note_key(_ id: NoteId) -> NoteKey? {
        NdbTxn(ndb: self, with: { txn in lookup_note_key_with_txn(id, txn: txn) }).value
    }

    func lookup_note(_ id: NoteId) -> NdbTxn<NdbNote?> {
        return NdbTxn(ndb: self) { txn in
            lookup_note_with_txn_inner(id: id, txn: txn)
        }
    }

    func lookup_profile(_ pubkey: Pubkey) -> NdbTxn<ProfileRecord?> {
        return NdbTxn(ndb: self) { txn in
            lookup_profile_with_txn_inner(pubkey: pubkey, txn: txn)
        }
    }

    func lookup_profile_with_txn<Y>(_ pubkey: Pubkey, txn: NdbTxn<Y>) -> ProfileRecord? {
        lookup_profile_with_txn_inner(pubkey: pubkey, txn: txn)
    }
    
    func process_client_event(_ str: String) -> Bool {
        return str.withCString { cstr in
            return ndb_process_client_event(ndb.ndb, cstr, Int32(str.utf8.count)) != 0
        }
    }

    func write_profile_last_fetched(pubkey: Pubkey, fetched_at: UInt64) {
        let _ = pubkey.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> () in
            guard let p = ptr.baseAddress else { return }
            ndb_write_last_profile_fetch(ndb.ndb, p, fetched_at)
        }
    }

    func read_profile_last_fetched<Y>(txn: NdbTxn<Y>, pubkey: Pubkey) -> UInt64? {
        return pubkey.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> UInt64? in
            guard let p = ptr.baseAddress else { return nil }
            let res = ndb_read_last_profile_fetch(&txn.txn, p)
            if res == 0 {
                return nil
            }

            return res
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

    func search_profile<Y>(_ search: String, limit: Int, txn: NdbTxn<Y>) -> [Pubkey] {
        var pks = Array<Pubkey>()

        return search.withCString { q in
            var s = ndb_search()
            guard ndb_search_profile(&txn.txn, &s, q) != 0 else {
                return pks
            }

            defer { ndb_search_profile_end(&s) }
            pks.append(Pubkey(Data(bytes: &s.key.pointee.id.0, count: 32)))

            var n = limit
            while n > 0 {
                guard ndb_search_profile_next(&s) != 0 else {
                    return pks
                }
                pks.append(Pubkey(Data(bytes: &s.key.pointee.id.0, count: 32)))

                n -= 1
            }

            return pks
        }
    }

    deinit {
        ndb_destroy(ndb.ndb)
    }
}

#if DEBUG
func getDebugCheckedRoot<T: FlatBufferObject>(byteBuffer: inout ByteBuffer) throws -> T {
    return getRoot(byteBuffer: &byteBuffer)
}
#else
func getDebugCheckedRoot<T: FlatBufferObject>(byteBuffer: inout ByteBuffer) throws -> T {
    return getRoot(byteBuffer: &byteBuffer)
}
#endif

func remove_file_prefix(_ str: String) -> String {
    return str.replacingOccurrences(of: "file://", with: "")
}

