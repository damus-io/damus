//
//  Ndb.swift
//  damus
//
//  Created by William Casarin on 2023-08-25.
//

import Foundation
import OSLog

fileprivate let APPLICATION_GROUP_IDENTIFIER = "group.com.damus"

enum NdbSearchOrder {
    case oldest_first
    case newest_first
}


enum DatabaseError: Error {
    case failed_open

    var errorDescription: String? {
        switch self {
        case .failed_open:
            return "Failed to open database"
        }
    }
}

    
func subscription_cb(ctx: UnsafeMutableRawPointer?, subid: UInt64) -> Void {
    guard let ctx else { return }
    let ndb = Unmanaged<Ndb>.fromOpaque(ctx).takeUnretainedValue()
    ndb.sub_cb?(subid)
}

class Ndb {
    var ndb: ndb_t
    let path: String?
    let owns_db: Bool
    var generation: Int
    let sub_cb: ((UInt64) -> ())?
    private var closed: Bool

    var is_closed: Bool {
        self.closed || self.ndb.ndb == nil
    }
    static func safemode() -> Ndb? {
        guard let path = db_path ?? old_db_path else { return nil }

        // delete the database and start fresh
        if Self.db_files_exist(path: path) {
            let file_manager = FileManager.default
            for db_file in db_files {
                try? file_manager.removeItem(atPath: "\(path)/\(db_file)")
            }
        }

        let ndb = Ndb(path: path)
        guard let _ = ndb.open() else {
            return nil
        }

        return ndb
    }

    // NostrDB used to be stored on the app container's document directory
    static private var old_db_path: String? {
        guard let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.absoluteString else {
            return nil
        }
        return remove_file_prefix(path)
    }

    static var db_path: String? {
        // Use the `group.com.damus` container, so that it can be accessible from other targets
        // e.g. The notification service extension needs to access Ndb data, which is done through this shared file container.
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: APPLICATION_GROUP_IDENTIFIER) else {
            return nil
        }
        return remove_file_prefix(containerURL.absoluteString)
    }
    
    static private var db_files: [String] = ["data.mdb", "lock.mdb"]

    static var empty: Ndb {
        print("txn: NOSTRDB EMPTY")
        return Ndb(ndb: ndb_t(ndb: nil))
    }

    func open() -> ndb_t? {
        var ndb_p: OpaquePointer? = nil

        let ingest_threads: Int32 = 4
        var mapsize: Int = 1024 * 1024 * 1024 * 32
        
        if path == nil && owns_db {
            // `nil` path indicates the default path will be used.
            // The default path changed over time, so migrate the database to the new location if needed
            do {
                try Self.migrate_db_location_if_needed()
            }
            catch {
                // If it fails to migrate, the app can still run without serious consequences. Log instead.
                Log.error("Error migrating NostrDB to new file container", for: .storage)
            }
        }
        
        guard let db_path = Self.db_path,
              owns_db || Self.db_files_exist(path: db_path) else {
            return nil      // If the caller claims to not own the DB file, and the DB files do not exist, then we should not initialize Ndb
        }

        guard let path = path.map(remove_file_prefix) ?? Ndb.db_path else {
            return nil
        }

        let ok = path.withCString { testdir in
            var ok = false
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            while !ok && mapsize > 1024 * 1024 * 700 {
                var cfg = ndb_config(flags: 0, ingester_threads: ingest_threads, mapsize: mapsize, filter_context: nil, ingest_filter: nil, sub_cb_ctx: ctx, sub_cb: subscription_cb)
                ok = ndb_init(&ndb_p, testdir, &cfg) != 0
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
        return self.ndb
    }

    init(path: String? = nil, owns_db_file: Bool = true, sub_cb: ((UInt64) -> ())? = nil) {
        self.generation = 0
        self.path = path
        self.owns_db = owns_db_file
        self.closed = false
        self.sub_cb = sub_cb
        self.ndb = ndb_t()
    }
    
    private static func migrate_db_location_if_needed() throws {
        guard let old_db_path, let db_path else {
            throw Errors.cannot_find_db_path
        }
        
        let file_manager = FileManager.default
        
        let old_db_files_exist = Self.db_files_exist(path: old_db_path)
        let new_db_files_exist = Self.db_files_exist(path: db_path)
        
        // Migration rules:
        // 1. If DB files exist in the old path but not the new one, move files to the new path
        // 2. If files do not exist anywhere, do nothing (let new DB be initialized)
        // 3. If files exist in the new path, but not the old one, nothing needs to be done
        // 4. If files exist on both, do nothing.
        // Scenario 4 likely means that user has downgraded and re-upgraded.
        // Although it might make sense to get the most recent DB, it might lead to data loss.
        // If we leave both intact, it makes it easier to fix later, as no data loss would occur.
        if old_db_files_exist && !new_db_files_exist {
            Log.info("Migrating NostrDB to new file location…", for: .storage)
            do {
                try db_files.forEach { db_file in
                    let old_path = "\(old_db_path)/\(db_file)"
                    let new_path = "\(db_path)/\(db_file)"
                    try file_manager.moveItem(atPath: old_path, toPath: new_path)
                }
                Log.info("NostrDB files successfully migrated to the new location", for: .storage)
            } catch {
                throw Errors.db_file_migration_error
            }
        }
    }
    
    private static func db_files_exist(path: String) -> Bool {
        return db_files.allSatisfy { FileManager.default.fileExists(atPath: "\(path)/\($0)") }
    }

    init(ndb: ndb_t) {
        self.ndb = ndb
        self.generation = 0
        self.path = nil
        self.owns_db = true
        self.closed = false
        self.sub_cb = nil
    }
    
    func close() {
        guard !self.is_closed else { return }
        self.closed = true
        print("txn: CLOSING NOSTRDB")
        ndb_destroy(self.ndb.ndb)
        self.generation += 1
        print("txn: NOSTRDB CLOSED")
    }

    func reopen() -> Bool {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard self.is_closed, let db = self.open() else {
            return false
        }
        
        print("txn: NOSTRDB REOPENED (gen \(generation))")

        self.closed = false
        self.ndb = db
        return true
    }
    
    func poll_for_notes(subid: Int64, capacity: Int) -> [NoteKey] {
        var buf = Array<UInt64>.init(repeating: 0, count: capacity)

        let r = buf.withUnsafeMutableBufferPointer { bytes in
            return ndb_poll_for_notes(self.ndb.ndb, UInt64(subid), bytes.baseAddress, Int32(capacity))
        }
        
        guard r != 0 else {
            return []
        }

        return Array(buf.prefix(Int(r)))
    }

    func lookup_blocks_by_key_with_txn<Y>(_ key: NoteKey, txn: NdbTxn<Y>) -> NdbBlocks? {
        guard let blocks = ndb_get_blocks_by_key(self.ndb.ndb, &txn.txn, key) else {
            return nil
        }

        return NdbBlocks(ptr: blocks)
    }

    func lookup_blocks_by_key(_ key: NoteKey) -> NdbTxn<NdbBlocks?>? {
        NdbTxn(ndb: self) { txn in
            lookup_blocks_by_key_with_txn(key, txn: txn)
        }
    }

    func lookup_note_by_key_with_txn<Y>(_ key: NoteKey, txn: NdbTxn<Y>) -> NdbNote? {
        var size: Int = 0
        guard let note_p = ndb_get_note_by_key(&txn.txn, key, &size) else {
            return nil
        }
        let ptr = ndb_note_ptr(ptr: note_p)
        return NdbNote(note: ptr, size: size, owned: false, key: key)
    }

    func text_search(query: String, limit: Int = 32, order: NdbSearchOrder = .newest_first) -> [NoteKey] {
        guard let txn = NdbTxn(ndb: self) else { return [] }
        var results = ndb_text_search_results()
        let res = query.withCString { q in
            let order = order == .newest_first ? NDB_ORDER_DESCENDING : NDB_ORDER_ASCENDING
            var config = ndb_text_search_config(order: order, limit: Int32(limit))
            return ndb_text_search(&txn.txn, q, &results, &config)
        }

        if res == 0 {
            return []
        }

        var note_ids = [NoteKey]()
        for i in 0..<results.num_results {
            // seriously wtf
            switch i {
            case 0: note_ids.append(results.results.0.key.note_id)
            case 1: note_ids.append(results.results.1.key.note_id)
            case 2: note_ids.append(results.results.2.key.note_id)
            case 3: note_ids.append(results.results.3.key.note_id)
            case 4: note_ids.append(results.results.4.key.note_id)
            case 5: note_ids.append(results.results.5.key.note_id)
            case 6: note_ids.append(results.results.6.key.note_id)
            case 7: note_ids.append(results.results.7.key.note_id)
            case 8: note_ids.append(results.results.8.key.note_id)
            case 9: note_ids.append(results.results.9.key.note_id)
            case 10: note_ids.append(results.results.10.key.note_id)
            case 11: note_ids.append(results.results.11.key.note_id)
            case 12: note_ids.append(results.results.12.key.note_id)
            case 13: note_ids.append(results.results.13.key.note_id)
            case 14: note_ids.append(results.results.14.key.note_id)
            case 15: note_ids.append(results.results.15.key.note_id)
            case 16: note_ids.append(results.results.16.key.note_id)
            case 17: note_ids.append(results.results.17.key.note_id)
            case 18: note_ids.append(results.results.18.key.note_id)
            case 19: note_ids.append(results.results.19.key.note_id)
            case 20: note_ids.append(results.results.20.key.note_id)
            default:
                break
            }
        }

        return note_ids
    }

    func lookup_note_by_key(_ key: NoteKey) -> NdbTxn<NdbNote?>? {
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
            var size: Int = 0
            guard let baseAddress = ptr.baseAddress,
                  let note_p = ndb_get_note_by_id(&txn.txn, baseAddress, &size, &key) else {
                return nil
            }
            let ptr = ndb_note_ptr(ptr: note_p)
            return NdbNote(note: ptr, size: size, owned: false, key: key)
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

    func lookup_profile_by_key(key: ProfileKey) -> NdbTxn<ProfileRecord?>? {
        return NdbTxn(ndb: self) { txn in
            lookup_profile_by_key_inner(key, txn: txn)
        }
    }

    func lookup_note_with_txn<Y>(id: NoteId, txn: NdbTxn<Y>) -> NdbNote? {
        lookup_note_with_txn_inner(id: id, txn: txn)
    }

    func lookup_profile_key(_ pubkey: Pubkey) -> ProfileKey? {
        guard let txn = NdbTxn(ndb: self, with: { txn in
            lookup_profile_key_with_txn(pubkey, txn: txn)
        }) else {
            return nil
        }

        return txn.value
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
        guard !closed else { return nil }
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
        guard let txn = NdbTxn(ndb: self, with: { txn in
            lookup_note_key_with_txn(id, txn: txn)
        }) else {
            return nil
        }

        return txn.value
    }

    func lookup_note(_ id: NoteId, txn_name: String? = nil) -> NdbTxn<NdbNote?>? {
        NdbTxn(ndb: self, name: txn_name) { txn in
            lookup_note_with_txn_inner(id: id, txn: txn)
        }
    }

    func lookup_profile(_ pubkey: Pubkey, txn_name: String? = nil) -> NdbTxn<ProfileRecord?>? {
        NdbTxn(ndb: self, name: txn_name) { txn in
            lookup_profile_with_txn_inner(pubkey: pubkey, txn: txn)
        }
    }

    func lookup_profile_with_txn<Y>(_ pubkey: Pubkey, txn: NdbTxn<Y>) -> ProfileRecord? {
        lookup_profile_with_txn_inner(pubkey: pubkey, txn: txn)
    }
    
    func process_client_event(_ str: String) -> Bool {
        guard !self.is_closed else { return false }
        return str.withCString { cstr in
            return ndb_process_client_event(ndb.ndb, cstr, Int32(str.utf8.count)) != 0
        }
    }

    func write_profile_last_fetched(pubkey: Pubkey, fetched_at: UInt64) {
        guard !closed else { return }
        let _ = pubkey.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> () in
            guard let p = ptr.baseAddress else { return }
            ndb_write_last_profile_fetch(ndb.ndb, p, fetched_at)
        }
    }

    func read_profile_last_fetched<Y>(txn: NdbTxn<Y>, pubkey: Pubkey) -> UInt64? {
        guard !closed else { return nil }
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
        guard !is_closed else { return false }
        return str.withCString { cstr in
            return ndb_process_event(ndb.ndb, cstr, Int32(str.utf8.count)) != 0
        }
    }

    func process_events(_ str: String) -> Bool {
        guard !is_closed else { return false }
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
    
    enum Errors: Error {
        case cannot_find_db_path
        case db_file_migration_error
    }

    deinit {
        print("txn: Ndb de-init")
        self.close()
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

