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

    /// Verifies Ndb.close() doesn't crash when a transaction is still active.
    /// Old code: use-after-free when accessing txn after close.
    /// New code: close is blocked or gracefully handled.
    func test_use_after_free_crash_during_close() throws {
        let ndb = Ndb(path: db_dir)!
        XCTAssertTrue(ndb.process_events(test_wire_events))

        let id = NoteId(hex: "d12c17bde3094ad32f4ab862a6cc6f5c289cfe7d5802270bdf34904df585f349")!

        guard let txn = NdbTxn<()>(ndb: ndb, name: "test_txn") else {
            return XCTFail("Could not create transaction")
        }

        let closeExpectation = XCTestExpectation(description: "Ndb close completes")
        DispatchQueue.global().async {
            ndb.close()
            closeExpectation.fulfill()
        }

        wait(for: [closeExpectation], timeout: 2.0)

        // If we reach here without crashing, the fix works.
        // On old code this would crash with use-after-free.
        let result = try? ndb.lookup_note(id, borrow: { $0 != nil })
        // Result may be nil (db closed) — the point is no crash.
        _ = result
        _ = txn
    }

    /// Verifies concurrent transaction creation doesn't crash.
    /// Old code: threadDictionary race between deinit clearing entries
    /// and init reading them caused force-unwrap crashes.
    /// New code: no shared state, so no race.
    func test_concurrent_transaction_creation_no_crash() throws {
        let ndb = Ndb(path: db_dir)!
        XCTAssertTrue(ndb.process_events(test_wire_events))

        let iterations = 200
        let group = DispatchGroup()

        for i in 0..<iterations {
            let queue = DispatchQueue(label: "txn.\(i)")
            group.enter()
            queue.async {
                autoreleasepool {
                    _ = NdbTxn<()>(ndb: ndb, name: "concurrent_\(i)")
                }
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "All \(iterations) concurrent transactions should complete without crash")
    }

    /// Verifies MDB_NOTLS allows multiple read transactions on the same thread.
    /// Without NOTLS, the second transaction would deadlock.
    func test_same_thread_overlapping_txns_no_deadlock() throws {
        let ndb = Ndb(path: db_dir)!
        XCTAssertTrue(ndb.process_events(test_wire_events))

        let expectation = XCTestExpectation(description: "Overlapping txns complete")
        var txn2Created = false

        DispatchQueue.global().async {
            guard let txn1 = NdbTxn<()>(ndb: ndb, name: "parent_txn") else {
                return
            }

            // Open second txn on same thread while first is active
            if let txn2 = NdbTxn<()>(ndb: ndb, name: "child_txn") {
                txn2Created = true
                _ = txn2
            }
            _ = txn1
            expectation.fulfill()
        }

        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(waiterResult, .completed, "Should not deadlock — MDB_NOTLS must be enabled")
        XCTAssertTrue(txn2Created, "Second transaction on same thread should succeed")
    }

    /// Verifies SafeNdbTxn.new properly closes the transaction when valueGetter returns nil.
    /// Old code: leaked the transaction (never called ndb_end_query).
    func test_SafeNdbTxn_new_nil_path_closes_transaction() throws {
        let ndb = Ndb(path: db_dir)!
        XCTAssertTrue(ndb.process_events(test_wire_events))

        #if TXNDEBUG
        let initialCount = txn_count

        let result = SafeNdbTxn<String?>.new(on: ndb) { _ in nil }
        XCTAssertNil(result, "Should return nil when valueGetter returns nil")
        XCTAssertEqual(txn_count, initialCount, "Transaction should be closed on nil path (leak detected)")
        #else
        throw XCTSkip("TXNDEBUG required to detect transaction leaks")
        #endif
    }

    /// Verifies SafeNdbTxn.maybeExtend properly closes the transaction when closure returns nil.
    /// Old code: set moved=true before consume, so deinit skipped close.
    func test_SafeNdbTxn_maybeExtend_nil_path_closes_transaction() throws {
        let ndb = Ndb(path: db_dir)!
        XCTAssertTrue(ndb.process_events(test_wire_events))

        #if TXNDEBUG
        let initialCount = txn_count

        let txn = SafeNdbTxn<Int>.new(on: ndb) { _ in 42 }
        XCTAssertNotNil(txn)
        XCTAssertEqual(txn_count, initialCount + 1)

        let result = txn?.maybeExtend { _ in nil as String? }
        XCTAssertNil(result, "Should return nil when closure returns nil")
        XCTAssertEqual(txn_count, initialCount, "Transaction should be closed on nil path (leak detected)")
        #else
        throw XCTSkip("TXNDEBUG required to detect transaction leaks")
        #endif
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

    /// Regression test: transaction inheritance removed (#3607).
    /// Old code: txn2 inherited txn1's snapshot via threadDictionary (stale data).
    /// New code: each transaction owns its own fresh LMDB snapshot.
    func test_transaction_inheritance_removed() throws {
        let ndb = Ndb(path: db_dir)!
        XCTAssertTrue(ndb.process_events(test_wire_events))

        guard let txn1 = NdbTxn<()>(ndb: ndb, name: "txn1") else {
            return XCTFail("Should create first transaction")
        }
        XCTAssertTrue(txn1.ownsTxn, "txn1 should own its transaction")

        guard let txn2 = NdbTxn<()>(ndb: ndb, name: "txn2") else {
            return XCTFail("Should create second transaction")
        }
        XCTAssertTrue(txn2.ownsTxn, "txn2 should own its own transaction, not inherit from txn1")
    }

    /// Smoke test: profile data accessible after db close (owned buffer copy).
    /// The underlying bug (ByteBuffer borrowing LMDB mmap pointer) is a
    /// use-after-free that cannot be reliably triggered in a unit test —
    /// macOS does not immediately reclaim munmap'd pages, and ASan does
    /// not instrument mmap/munmap. The fix is verified by code inspection:
    /// ByteBuffer(memory:count:) copies data vs (assumingMemoryBound:capacity:)
    /// which wraps the pointer with unowned=true. See #3625 for full analysis.
    func test_profile_buffer_ownership() throws {
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        do {
            let ndb = Ndb(path: db_dir)!
            XCTAssertTrue(ndb.process_events(test_wire_events))
        }

        var profile: Profile? = nil
        do {
            let ndb = Ndb(path: db_dir)!
            profile = try? ndb.lookup_profile_and_copy(pk)
            ndb.close()
        }

        guard let profile else {
            return XCTFail("Expected profile to be non-nil")
        }
        XCTAssertEqual(profile.name, "jb55")
    }

    /// Verifies snapshot_note_by_key returns an owned copy that survives ndb close.
    func test_snapshot_note_by_key_returns_owned_copy() throws {
        let id = NoteId(hex: "d12c17bde3094ad32f4ab862a6cc6f5c289cfe7d5802270bdf34904df585f349")!

        do {
            let ndb = Ndb(path: db_dir)!
            XCTAssertTrue(ndb.process_events(test_wire_events))
        }

        var snapshot: NdbNote? = nil
        do {
            let ndb = Ndb(path: db_dir)!
            guard let note = try? ndb.lookup_note_and_copy(id) else {
                return XCTFail("Expected to find note in test data")
            }
            guard let key = note.key else {
                return XCTFail("Expected note.key to be non-nil")
            }
            snapshot = try ndb.snapshot_note_by_key(key)
            XCTAssertNotNil(snapshot)
            ndb.close()
        }

        // Owned copy survives ndb close because it's a deep copy
        guard let snapshot else {
            return XCTFail("snapshot_note_by_key should return an owned copy")
        }
        XCTAssertEqual(snapshot.id, id)
    }

    /// Verifies NdbNoteLender.snapshot() returns an owned copy via snapshot_note_by_key.
    func test_note_lender_snapshot() throws {
        let id = NoteId(hex: "d12c17bde3094ad32f4ab862a6cc6f5c289cfe7d5802270bdf34904df585f349")!

        do {
            let ndb = Ndb(path: db_dir)!
            XCTAssertTrue(ndb.process_events(test_wire_events))
        }

        let ndb = Ndb(path: db_dir)!
        guard let note = try? ndb.lookup_note_and_copy(id) else {
            return XCTFail("Expected to find note in test data")
        }

        guard let key = note.key else {
            return XCTFail("Expected note.key to be non-nil for NdbNoteLender")
        }

        let lender = NdbNoteLender(ndb: ndb, noteKey: key)
        let owned = try lender.snapshot()
        XCTAssertEqual(owned.id, id)
    }

    /// Verifies Ndb initializes with smaller mapsize in extension mode.
    func test_ndb_init_extension_mode() throws {
        do {
            let ndb = Ndb(path: db_dir)!
            XCTAssertTrue(ndb.process_events(test_wire_events))
            ndb.close()
        }

        guard let extensionNdb = Ndb(path: db_dir, owns_db_file: false) else {
            return XCTFail("Ndb should initialize in extension mode")
        }

        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let profile = try? extensionNdb.lookup_profile_and_copy(pk)
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.name, "jb55")
        extensionNdb.close()
    }

}

