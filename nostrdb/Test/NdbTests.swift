//
//  NDBIterTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-07-21.
//

import XCTest
@testable import damus

func test_ndb_dir() -> String? {
    do {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        return remove_file_prefix(tempDir.absoluteString)
    } catch {
        return nil
    }
}

final class NdbTests: XCTestCase {
    var db_dir: String = ""

    override func setUpWithError() throws {
        guard let db = test_ndb_dir() else {
            XCTFail("Could not create temp directory")
            return
        }
        db_dir = db
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_decode_eose() throws {
        let json = "[\"EOSE\",\"DC268DBD-55DA-458A-B967-540925AF3497\"]"
        let resp = decode_nostr_event(txt: json)
        XCTAssertNotNil(resp)
    }

    func test_decode_command_result() throws {
        let json = "[\"OK\",\"b1d8f68d39c07ce5c5ea10c235100d529b2ed2250140b36a35d940b712dc6eff\",true,\"\"]"
        let resp = decode_nostr_event(txt: json)
        XCTAssertNotNil(resp)

    }

    func test_profile_creation() {
        let profile = make_test_profile()
        XCTAssertEqual(profile.name, "jb55")
    }

    func test_ndb_init() {

        do {
            let ndb = Ndb(path: db_dir)!
            let ok = ndb.process_events(test_wire_events)
            XCTAssertTrue(ok)
        }

        do {
            let ndb = Ndb(path: db_dir)!
            let id = NoteId(hex: "d12c17bde3094ad32f4ab862a6cc6f5c289cfe7d5802270bdf34904df585f349")!
            let note = try? ndb.lookup_note_and_copy(id)
            XCTAssertNotNil(note)
            guard let note else { return }
            let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
            XCTAssertEqual(note.pubkey, pk)

            let profile = try? ndb.lookup_profile_and_copy(pk)
            let lnurl = try? ndb.lookup_profile_lnurl(pk)
            XCTAssertNotNil(profile)
            guard let profile else { return }

            XCTAssertEqual(profile.name, "jb55")
            XCTAssertEqual(lnurl, nil)
        }


    }

    func test_ndb_search() throws {
        do {
            let ndb = Ndb(path: db_dir)!
            let ok = ndb.process_events(test_wire_events)
            XCTAssertTrue(ok)
        }
        
        do {
            let ndb = Ndb(path: db_dir)!
            let note_ids = (try? ndb.text_search(query: "barked")) ?? []
            XCTAssertEqual(note_ids.count, 1)
            let expected_note_id = NoteId(hex: "b17a540710fe8495b16bfbaf31c6962c4ba8387f3284a7973ad523988095417e")!
            guard note_ids.count > 0 else {
                XCTFail("Expected at least one note to be found")
                return
            }
            let note_id = try? ndb.lookup_note_by_key(note_ids[0], borrow: { maybeUnownedNote -> NoteId? in
                switch maybeUnownedNote {
                case .none: return nil
                case .some(let unownedNote): return unownedNote.id
                }
            })
            XCTAssertEqual(note_id, .some(expected_note_id))
        }
    }

    func test_ndb_note() throws {
        let note = NdbNote.owned_from_json(json: test_contact_list_json)
        XCTAssertNotNil(note)
        guard let note else { return }

        let id = NoteId(hex: "20d0ff27d6fcb13de8366328c5b1a7af26bcac07f2e558fbebd5e9242e608c09")!
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        XCTAssertEqual(note.id, id)
        XCTAssertEqual(note.pubkey, pubkey)

        XCTAssertEqual(note.count, 34328)
        XCTAssertEqual(note.kind, 3)
        XCTAssertEqual(note.created_at, 1689904312)

        let expected_count: UInt16 = 786
        XCTAssertEqual(note.tags.count, expected_count)
        XCTAssertEqual(note.tags.reduce(0, { sum, _ in sum + 1 }), expected_count)

        var tags = 0
        var total_count_stored = 0
        var total_count_iter = 0
        //let tags = note.tags()
        for tag in note.tags {
            total_count_stored += Int(tag.count)

            if tags == 0 || tags == 1 || tags == 2 {
                XCTAssertEqual(tag.count, 3)
            }

            if tags == 6 {
                XCTAssertEqual(tag.count, 2)
            }

            if tags == 7 {
                XCTAssertEqual(tag[2].string(), "wss://nostr-pub.wellorder.net")
            }

            for elem in tag {
                print("tag[\(tags)][\(elem.index)]")
                total_count_iter += 1
            }

            tags += 1
        }

        XCTAssertEqual(tags, 786)
        XCTAssertEqual(total_count_stored, total_count_iter)
    }
    
    /// Based on https://github.com/damus-io/damus/issues/1468
    /// Tests whether a JSON with optional escaped slash characters is correctly unescaped (In accordance to https://datatracker.ietf.org/doc/html/rfc8259#section-7)
    func test_decode_json_with_escaped_slashes() {
        let testJSONWithEscapedSlashes = "{\"tags\":[],\"pubkey\":\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\",\"content\":\"https:\\/\\/cdn.nostr.build\\/i\\/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg\",\"created_at\":1691864981,\"kind\":1,\"sig\":\"fc0033aa3d4df50b692a5b346fa816fdded698de2045e36e0642a021391468c44ca69c2471adc7e92088131872d4aaa1e90ea6e1ad97f3cc748f4aed96dfae18\",\"id\":\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\"}"
        let testNote = NdbNote.owned_from_json(json: testJSONWithEscapedSlashes)!
        XCTAssertEqual(testNote.content, "https://cdn.nostr.build/i/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg")
    }
    
    func test_inherited_transactions() throws {
        let ndb = Ndb(path: db_dir)!
        do {
            guard let txn1 = NdbTxn(ndb: ndb) else { return XCTAssert(false) }

            let ntxn = (Thread.current.threadDictionary.value(forKey: "ndb_txn") as? ndb_txn)!
            XCTAssertEqual(txn1.txn.lmdb, ntxn.lmdb)
            XCTAssertEqual(txn1.txn.mdb_txn, ntxn.mdb_txn)

            guard let txn2 = NdbTxn(ndb: ndb) else { return XCTAssert(false) }

            XCTAssertEqual(txn1.inherited, false)
            XCTAssertEqual(txn2.inherited, true)
        }

        let ndb_txn = Thread.current.threadDictionary.value(forKey: "ndb_txn")
        XCTAssertNil(ndb_txn)
    }

    func test_decode_perf() throws {
        // This is an example of a performance test case.
        self.measure {
            _ = NdbNote.owned_from_json(json: test_contact_list_json)
        }
    }

    func test_perf_old_decoding() {
        self.measure {
            let event = decode_nostr_event_json(test_contact_list_json)
            XCTAssertNotNil(event)
        }
    }

    func test_perf_old_iter()  {
        self.measure {
            let event = decode_nostr_event_json(test_contact_list_json)
            XCTAssertNotNil(event)
        }
    }

    func longer_iter(_ n: Int = 1000) -> XCTMeasureOptions {
        let opts = XCTMeasureOptions()
        opts.iterationCount = n
        return opts
    }

    // MARK: - Extension snapshot crash reproduction
    // Reproduces the #1 crash (40 devices): mdb_page_search_root SIGSEGV
    // in DamusNotificationService during profile lookup on snapshot database.

    /// Step 1: Does the basic extension flow work at all?
    /// Create a db, snapshot it, open snapshot with owns_db_file:false, query.
    func test_extension_snapshot_profile_lookup() throws {
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let snapshotDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_test_\(UUID().uuidString)")
        let snapshotPath = remove_file_prefix(snapshotDir.absoluteString)
        defer { try? FileManager.default.removeItem(at: snapshotDir) }

        // Create main db with profile data
        do {
            let ndb = Ndb(path: db_dir)!
            XCTAssertTrue(ndb.process_events(test_wire_events))
            Thread.sleep(forTimeInterval: 1.0)

            // Verify profile exists in source
            let profile = try? ndb.lookup_profile_and_copy(pk)
            XCTAssertNotNil(profile, "Profile should exist in source db")
            XCTAssertEqual(profile?.name, "jb55")

            // Snapshot to separate path (like DatabaseSnapshotManager does)
            try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
            try ndb.snapshot(path: snapshotPath)
            ndb.close()
        }

        // Open snapshot like the notification extension does (owns_db_file: false)
        do {
            guard let extNdb = Ndb(path: snapshotPath, owns_db_file: false) else {
                XCTFail("Extension Ndb should open snapshot successfully")
                return
            }

            // This is the exact code path that crashes on 40 devices:
            // lookup_profile → SafeNdbTxn.new → lookup_profile_with_txn_inner
            //   → ndb_lookup_tsid → mdb_page_search_root
            let profile = try? extNdb.lookup_profile_and_copy(pk)
            XCTAssertNotNil(profile, "Profile should be readable from snapshot")
            XCTAssertEqual(profile?.name, "jb55")
            extNdb.close()
        }
    }

    /// Step 2: What happens when snapshot directory is deleted while Ndb is open?
    /// Simulates DatabaseSnapshotManager.moveSnapshotToFinalDestination replacing
    /// the directory while the extension has the database open.
    func test_extension_snapshot_deleted_while_open() throws {
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let snapshotDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_race_\(UUID().uuidString)")
        let snapshotPath = remove_file_prefix(snapshotDir.absoluteString)
        defer { try? FileManager.default.removeItem(at: snapshotDir) }

        // Create and snapshot
        do {
            let ndb = Ndb(path: db_dir)!
            XCTAssertTrue(ndb.process_events(test_wire_events))
            Thread.sleep(forTimeInterval: 1.0)
            try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
            try ndb.snapshot(path: snapshotPath)
            ndb.close()
        }

        // Open snapshot (like extension)
        guard let extNdb = Ndb(path: snapshotPath, owns_db_file: false) else {
            XCTFail("Extension Ndb should open snapshot successfully")
            return
        }

        // Verify it works before deletion
        let profileBefore = try? extNdb.lookup_profile_and_copy(pk)
        XCTAssertNotNil(profileBefore, "Profile should work before directory deletion")

        // Simulate main app replacing snapshot: delete the directory
        // (This is what DatabaseSnapshotManager.moveSnapshotToFinalDestination does)
        try FileManager.default.removeItem(at: snapshotDir)

        // Query again — UNIX keeps mmap alive via open fd after unlink,
        // so the profile should still be accessible
        let profileAfter = try? extNdb.lookup_profile_and_copy(pk)
        XCTAssertNotNil(profileAfter, "Profile should survive directory deletion (UNIX fd semantics)")

        extNdb.close()
    }

    /// Step 3: What happens with delete + replace (full race simulation)?
    /// Delete snapshot dir, move a NEW snapshot in, then query through old handle.
    func test_extension_snapshot_replaced_while_open() throws {
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let snapshotDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_replace_\(UUID().uuidString)")
        let snapshotPath = remove_file_prefix(snapshotDir.absoluteString)
        defer { try? FileManager.default.removeItem(at: snapshotDir) }

        // Create and snapshot
        do {
            let ndb = Ndb(path: db_dir)!
            XCTAssertTrue(ndb.process_events(test_wire_events))
            Thread.sleep(forTimeInterval: 1.0)
            try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
            try ndb.snapshot(path: snapshotPath)
            ndb.close()
        }

        // Open snapshot (like extension)
        guard let extNdb = Ndb(path: snapshotPath, owns_db_file: false) else {
            XCTFail("Extension Ndb should open snapshot")
            return
        }

        // Verify baseline
        let profileBefore = try? extNdb.lookup_profile_and_copy(pk)
        XCTAssertNotNil(profileBefore)

        // Create a second snapshot in a temp location
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_temp_\(UUID().uuidString)")
        let tempPath = remove_file_prefix(tempDir.absoluteString)
        do {
            let ndb2 = Ndb(path: db_dir)!
            XCTAssertTrue(ndb2.process_events(test_wire_events))
            Thread.sleep(forTimeInterval: 1.0)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try ndb2.snapshot(path: tempPath)
            ndb2.close()
        }

        // Simulate DatabaseSnapshotManager.moveSnapshotToFinalDestination:
        // Step 1: Delete old snapshot
        try FileManager.default.removeItem(at: snapshotDir)
        // Step 2: Move new snapshot into same path
        try FileManager.default.moveItem(at: tempDir, to: snapshotDir)

        // Query through the OLD Ndb handle — files underneath have been replaced
        // but UNIX fd semantics keep the original mmap alive
        let profileAfter = try? extNdb.lookup_profile_and_copy(pk)
        XCTAssertNotNil(profileAfter, "Profile should survive directory replacement (UNIX fd semantics)")

        extNdb.close()
    }

    /// Step 4: What if the snapshot directory exists but data.mdb is missing?
    func test_extension_snapshot_no_data_file() throws {
        let snapshotDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_empty_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: snapshotDir) }
        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        let snapshotPath = remove_file_prefix(snapshotDir.absoluteString)

        // Open like extension — directory exists but no data.mdb
        let extNdb = Ndb(path: snapshotPath, owns_db_file: false)
        // Should return nil (db_file_exists check), not crash
        XCTAssertNil(extNdb, "Ndb should return nil when no data.mdb exists")
    }

    /// Step 5: What if data.mdb exists but is truncated/empty (0 bytes)?
    func test_extension_snapshot_truncated_data_file() throws {
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let snapshotDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_truncated_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: snapshotDir) }
        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        let snapshotPath = remove_file_prefix(snapshotDir.absoluteString)

        // Create an empty data.mdb file (0 bytes)
        XCTAssertTrue(FileManager.default.createFile(atPath: snapshotDir.appendingPathComponent("data.mdb").path, contents: Data()), "Failed to create empty data.mdb")

        // LMDB treats a 0-byte file as a new environment — opens successfully
        // but the database is empty, so profile lookup must return nil
        guard let extNdb = Ndb(path: snapshotPath, owns_db_file: false) else {
            // Also acceptable: Ndb may reject a 0-byte snapshot
            return
        }
        let profile = try? extNdb.lookup_profile_and_copy(pk)
        XCTAssertNil(profile, "Empty database should not contain any profiles")
        extNdb.close()
    }

    /// Step 6: What if data.mdb exists but contains garbage?
    func test_extension_snapshot_corrupted_data_file() throws {
        let snapshotDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_corrupt_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: snapshotDir) }
        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        let snapshotPath = remove_file_prefix(snapshotDir.absoluteString)

        // Create a data.mdb with garbage data (random bytes, page-sized)
        var garbage = Data(count: 4096 * 4) // 4 pages of garbage
        for i in 0..<garbage.count { garbage[i] = UInt8.random(in: 0...255) }
        try garbage.write(to: snapshotDir.appendingPathComponent("data.mdb"))

        // Garbage bytes won't have valid LMDB magic/meta pages — must be rejected
        let extNdb = Ndb(path: snapshotPath, owns_db_file: false)
        XCTAssertNil(extNdb, "Ndb should refuse to open a corrupted data.mdb")
        extNdb?.close()
    }

    /// Step 7: What if the snapshot is mid-write? Simulate by creating a valid snapshot
    /// then truncating data.mdb to half its size.
    func test_extension_snapshot_partially_written() throws {
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let snapshotDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_partial_\(UUID().uuidString)")
        let snapshotPath = remove_file_prefix(snapshotDir.absoluteString)
        defer { try? FileManager.default.removeItem(at: snapshotDir) }

        // Create a valid snapshot first
        do {
            let ndb = Ndb(path: db_dir)!
            XCTAssertTrue(ndb.process_events(test_wire_events))
            Thread.sleep(forTimeInterval: 1.0)
            try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
            try ndb.snapshot(path: snapshotPath)
            ndb.close()
        }

        // Truncate data.mdb to half its size (simulating interrupted write)
        let dataPath = snapshotDir.appendingPathComponent("data.mdb")
        let fullData = try Data(contentsOf: dataPath)
        let halfData = fullData.prefix(fullData.count / 2)
        try halfData.write(to: dataPath)
        print("Truncated data.mdb from \(fullData.count) to \(halfData.count) bytes")

        let extNdb = Ndb(path: snapshotPath, owns_db_file: false)
        XCTAssertNil(extNdb, "Ndb should refuse to open a truncated snapshot")
        extNdb?.close()
    }

    func test_iteration_perf() throws {
        guard let note = NdbNote.owned_from_json(json: test_contact_list_json) else {
            XCTAssert(false)
            return
        }


        self.measure {
            var count = 0
            var char_count = 0

            for tag in note.tags {
                for elem in tag {
                    print("iter_elem \(elem.string())")
                    for c in elem {
                        if char_count == 0 {
                            let ac = AsciiCharacter(c)
                            XCTAssertEqual(ac, "p")
                        } else if char_count == 0 {
                            XCTAssertEqual(c, 0x6c)
                        }
                        char_count += 1
                    }
                }
                count += 1
            }

            XCTAssertEqual(count, 786)
            XCTAssertEqual(char_count, 24370)
        }

    }

}

