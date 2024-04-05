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

class Ndb {
    var ndb: ndb_t
    let path: String?
    let owns_db: Bool
    var generation: Int
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

        guard let ndb = Ndb(path: path) else {
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
    
    static func open(path: String? = nil, owns_db_file: Bool = true) -> ndb_t? {
        var ndb_p: OpaquePointer? = nil

        let ingest_threads: Int32 = 4
        var mapsize: Int = 1024 * 1024 * 1024 * 32
        
        if path == nil && owns_db_file {
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
              owns_db_file || Self.db_files_exist(path: db_path) else {
            return nil      // If the caller claims to not own the DB file, and the DB files do not exist, then we should not initialize Ndb
        }

        guard let path = path.map(remove_file_prefix) ?? Ndb.db_path else {
            return nil
        }

        let ok = path.withCString { testdir in
            var ok = false
            while !ok && mapsize > 1024 * 1024 * 700 {
                var cfg = ndb_config(flags: 0, ingester_threads: ingest_threads, mapsize: mapsize, filter_context: nil, ingest_filter: nil, sub_cb_ctx: nil, sub_cb: nil)
                let res = ndb_init(&ndb_p, testdir, &cfg);
                let ok = res != 0;
                if !ok {
                    Log.error("ndb_init failed: %d, reducing mapsize from %d to %d", for: .storage, res, mapsize, mapsize / 2)
                    mapsize /= 2
                }
            }
            return ok
        }

        if !ok {
            return nil
        }

        return ndb_t(ndb: ndb_p)
    }

    init?(path: String? = nil, owns_db_file: Bool = true) {
        guard let db = Self.open(path: path, owns_db_file: owns_db_file) else {
            return nil
        }
        
        self.generation = 0
        self.path = path
        self.owns_db = owns_db_file
        self.ndb = db
        self.closed = false
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
        guard self.is_closed,
              let db = Self.open(path: self.path, owns_db_file: self.owns_db) else {
            return false
        }
        
        print("txn: NOSTRDB REOPENED (gen \(generation))")

        self.closed = false
        self.ndb = db
        return true
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

    func text_search(query: String, limit: Int = 128, order: NdbSearchOrder = .newest_first) -> [NoteKey] {
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
            case 21: note_ids.append(results.results.21.key.note_id)
            case 22: note_ids.append(results.results.22.key.note_id)
            case 23: note_ids.append(results.results.23.key.note_id)
            case 24: note_ids.append(results.results.24.key.note_id)
            case 25: note_ids.append(results.results.25.key.note_id)
            case 26: note_ids.append(results.results.26.key.note_id)
            case 27: note_ids.append(results.results.27.key.note_id)
            case 28: note_ids.append(results.results.28.key.note_id)
            case 29: note_ids.append(results.results.29.key.note_id)
            case 30: note_ids.append(results.results.30.key.note_id)
            case 31: note_ids.append(results.results.31.key.note_id)
            case 32: note_ids.append(results.results.32.key.note_id)
            case 33: note_ids.append(results.results.33.key.note_id)
            case 34: note_ids.append(results.results.34.key.note_id)
            case 35: note_ids.append(results.results.35.key.note_id)
            case 36: note_ids.append(results.results.36.key.note_id)
            case 37: note_ids.append(results.results.37.key.note_id)
            case 38: note_ids.append(results.results.38.key.note_id)
            case 39: note_ids.append(results.results.39.key.note_id)
            case 40: note_ids.append(results.results.40.key.note_id)
            case 41: note_ids.append(results.results.41.key.note_id)
            case 42: note_ids.append(results.results.42.key.note_id)
            case 43: note_ids.append(results.results.43.key.note_id)
            case 44: note_ids.append(results.results.44.key.note_id)
            case 45: note_ids.append(results.results.45.key.note_id)
            case 46: note_ids.append(results.results.46.key.note_id)
            case 47: note_ids.append(results.results.47.key.note_id)
            case 48: note_ids.append(results.results.48.key.note_id)
            case 49: note_ids.append(results.results.49.key.note_id)
            case 50: note_ids.append(results.results.50.key.note_id)
            case 51: note_ids.append(results.results.51.key.note_id)
            case 52: note_ids.append(results.results.52.key.note_id)
            case 53: note_ids.append(results.results.53.key.note_id)
            case 54: note_ids.append(results.results.54.key.note_id)
            case 55: note_ids.append(results.results.55.key.note_id)
            case 56: note_ids.append(results.results.56.key.note_id)
            case 57: note_ids.append(results.results.57.key.note_id)
            case 58: note_ids.append(results.results.58.key.note_id)
            case 59: note_ids.append(results.results.59.key.note_id)
            case 60: note_ids.append(results.results.60.key.note_id)
            case 61: note_ids.append(results.results.61.key.note_id)
            case 62: note_ids.append(results.results.62.key.note_id)
            case 63: note_ids.append(results.results.63.key.note_id)
            case 64: note_ids.append(results.results.64.key.note_id)
            case 65: note_ids.append(results.results.65.key.note_id)
            case 66: note_ids.append(results.results.66.key.note_id)
            case 67: note_ids.append(results.results.67.key.note_id)
            case 68: note_ids.append(results.results.68.key.note_id)
            case 69: note_ids.append(results.results.69.key.note_id)
            case 70: note_ids.append(results.results.70.key.note_id)
            case 71: note_ids.append(results.results.71.key.note_id)
            case 72: note_ids.append(results.results.72.key.note_id)
            case 73: note_ids.append(results.results.73.key.note_id)
            case 74: note_ids.append(results.results.74.key.note_id)
            case 75: note_ids.append(results.results.75.key.note_id)
            case 76: note_ids.append(results.results.76.key.note_id)
            case 77: note_ids.append(results.results.77.key.note_id)
            case 78: note_ids.append(results.results.78.key.note_id)
            case 79: note_ids.append(results.results.79.key.note_id)
            case 80: note_ids.append(results.results.80.key.note_id)
            case 81: note_ids.append(results.results.81.key.note_id)
            case 82: note_ids.append(results.results.82.key.note_id)
            case 83: note_ids.append(results.results.83.key.note_id)
            case 84: note_ids.append(results.results.84.key.note_id)
            case 85: note_ids.append(results.results.85.key.note_id)
            case 86: note_ids.append(results.results.86.key.note_id)
            case 87: note_ids.append(results.results.87.key.note_id)
            case 88: note_ids.append(results.results.88.key.note_id)
            case 89: note_ids.append(results.results.89.key.note_id)
            case 90: note_ids.append(results.results.90.key.note_id)
            case 91: note_ids.append(results.results.91.key.note_id)
            case 92: note_ids.append(results.results.92.key.note_id)
            case 93: note_ids.append(results.results.93.key.note_id)
            case 94: note_ids.append(results.results.94.key.note_id)
            case 95: note_ids.append(results.results.95.key.note_id)
            case 96: note_ids.append(results.results.96.key.note_id)
            case 97: note_ids.append(results.results.97.key.note_id)
            case 98: note_ids.append(results.results.98.key.note_id)
            case 99: note_ids.append(results.results.99.key.note_id)
            case 100: note_ids.append(results.results.100.key.note_id)
            case 101: note_ids.append(results.results.101.key.note_id)
            case 102: note_ids.append(results.results.102.key.note_id)
            case 103: note_ids.append(results.results.103.key.note_id)
            case 104: note_ids.append(results.results.104.key.note_id)
            case 105: note_ids.append(results.results.105.key.note_id)
            case 106: note_ids.append(results.results.106.key.note_id)
            case 107: note_ids.append(results.results.107.key.note_id)
            case 108: note_ids.append(results.results.108.key.note_id)
            case 109: note_ids.append(results.results.109.key.note_id)
            case 110: note_ids.append(results.results.110.key.note_id)
            case 111: note_ids.append(results.results.111.key.note_id)
            case 112: note_ids.append(results.results.112.key.note_id)
            case 113: note_ids.append(results.results.113.key.note_id)
            case 114: note_ids.append(results.results.114.key.note_id)
            case 115: note_ids.append(results.results.115.key.note_id)
            case 116: note_ids.append(results.results.116.key.note_id)
            case 117: note_ids.append(results.results.117.key.note_id)
            case 118: note_ids.append(results.results.118.key.note_id)
            case 119: note_ids.append(results.results.119.key.note_id)
            case 120: note_ids.append(results.results.120.key.note_id)
            case 121: note_ids.append(results.results.121.key.note_id)
            case 122: note_ids.append(results.results.122.key.note_id)
            case 123: note_ids.append(results.results.123.key.note_id)
            case 124: note_ids.append(results.results.124.key.note_id)
            case 125: note_ids.append(results.results.125.key.note_id)
            case 126: note_ids.append(results.results.126.key.note_id)
            case 127: note_ids.append(results.results.127.key.note_id)
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

