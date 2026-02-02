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

    // MARK: - Extension Context Tests

    /// Tests that extension bundle path detection works correctly.
    func test_extension_bundle_path_detection() {
        // Main app paths should NOT be detected as extensions
        let mainAppPaths = [
            "/var/containers/Bundle/Application/UUID/Damus.app",
            "/Applications/Damus.app",
            "/path/to/App.app"
        ]
        for path in mainAppPaths {
            XCTAssertFalse(path.hasSuffix(".appex"), "Main app path should not be detected as extension: \(path)")
        }

        // Extension paths SHOULD be detected as extensions
        let extensionPaths = [
            "/var/containers/Bundle/Application/UUID/Damus.app/PlugIns/DamusNotificationService.appex",
            "/var/containers/Bundle/Application/UUID/Damus.app/PlugIns/HighlighterActionExtension.appex",
            "/path/to/App.app/PlugIns/SomeExtension.appex"
        ]
        for path in extensionPaths {
            XCTAssertTrue(path.hasSuffix(".appex"), "Extension path should be detected: \(path)")
        }
    }

    /// Tests that Ndb initializes correctly when owns_db_file=false (extension mode).
    ///
    /// Extension mode uses NDB_FLAG_READONLY which:
    /// - Skips writer/ingester thread creation (prevents prot_queue crashes)
    /// - Uses smaller mapsize (prevents memory pressure in 24MB limit)
    /// - Still allows read operations
    func test_ndb_init_extension_mode() throws {
        // First, create a database with some data using full mode
        let ndb = Ndb(path: db_dir, owns_db_file: true)!
        let ok = ndb.process_events(test_wire_events)
        XCTAssertTrue(ok)
        ndb.close()

        // Now open in "extension mode" (owns_db_file=false)
        // This uses NDB_FLAG_READONLY which skips thread creation
        guard let extensionNdb = Ndb(path: db_dir, owns_db_file: false) else {
            XCTFail("Ndb should initialize in extension mode")
            return
        }

        // Verify we can still read data (readonly mode supports reads)
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let profile = try? extensionNdb.lookup_profile_and_copy(pk)
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.name, "jb55")

        // Also verify note lookup works
        let noteId = NoteId(hex: "d12c17bde3094ad32f4ab862a6cc6f5c289cfe7d5802270bdf34904df585f349")!
        let note = try? extensionNdb.lookup_note_and_copy(noteId)
        XCTAssertNotNil(note)

        extensionNdb.close()
    }

    /// Tests that readonly mode can be opened and closed rapidly without crashes.
    ///
    /// This regression test verifies the fix for the 5h0 crash (prot_queue_pop_all)
    /// where thread creation in extension context caused race conditions.
    func test_readonly_mode_rapid_open_close() throws {
        // First create database with data
        let ndb = Ndb(path: db_dir, owns_db_file: true)!
        let ok = ndb.process_events(test_wire_events)
        XCTAssertTrue(ok)
        ndb.close()

        // Rapidly open and close in readonly mode multiple times
        // This would crash before the fix due to thread races
        for _ in 0..<10 {
            guard let readonlyNdb = Ndb(path: db_dir, owns_db_file: false) else {
                XCTFail("Should be able to open in readonly mode")
                return
            }

            // Do a quick read
            let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
            _ = try? readonlyNdb.lookup_profile_and_copy(pk)

            readonlyNdb.close()
        }
    }

    /// Tests that write operations fail in readonly mode.
    ///
    /// Readonly mode (NDB_FLAG_READONLY) should reject write operations
    /// to prevent accessing uninitialized writer/ingester threads.
    func test_readonly_mode_rejects_writes() throws {
        // First create database with data
        let ndb = Ndb(path: db_dir, owns_db_file: true)!
        let ok = ndb.process_events(test_wire_events)
        XCTAssertTrue(ok)
        ndb.close()

        // Open in readonly mode
        guard let readonlyNdb = Ndb(path: db_dir, owns_db_file: false) else {
            XCTFail("Should be able to open in readonly mode")
            return
        }

        // Attempt to write - should fail (return false)
        let writeResult = readonlyNdb.process_events(test_wire_events)
        XCTAssertFalse(writeResult, "Write operations should fail in readonly mode")

        readonlyNdb.close()
    }

    // MARK: - Transaction Retention Tests

    /// Tests that transactions retain ndb and prevent premature close.
    ///
    /// This verifies the fix for the 5nt crash (lookup_note_with_txn_inner use-after-free)
    /// where ndb was destroyed while transactions still held pointers to LMDB state.
    func test_transaction_retains_ndb() throws {
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let noteId = NoteId(hex: "d12c17bde3094ad32f4ab862a6cc6f5c289cfe7d5802270bdf34904df585f349")!

        // First: populate the database and close (flushes async writes)
        do {
            let ndb = Ndb(path: db_dir)!
            let ok = ndb.process_events(test_wire_events)
            XCTAssertTrue(ok)
        }

        // Second: reopen and verify lookups work with transaction retention
        do {
            let ndb = Ndb(path: db_dir)!
            let result: Pubkey? = try? ndb.lookup_note(noteId) { maybeNote in
                switch maybeNote {
                case .none: return nil
                case .some(let note): return note.pubkey
                }
            }

            XCTAssertNotNil(result, "Should retrieve note")
            XCTAssertEqual(result, pk, "Note should have correct pubkey")
        }
    }

    /// Tests that close waits for active transactions to complete.
    ///
    /// Simulates the crash scenario: transaction is active, close is called.
    /// The close should wait for the transaction to complete.
    func test_close_waits_for_active_transaction() throws {
        let noteId = NoteId(hex: "d12c17bde3094ad32f4ab862a6cc6f5c289cfe7d5802270bdf34904df585f349")!
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        // First: populate the database and close (flushes async writes)
        do {
            let ndb = Ndb(path: db_dir)!
            let ok = ndb.process_events(test_wire_events)
            XCTAssertTrue(ok)
        }

        // Second: reopen and test close-during-transaction behavior
        let ndb = Ndb(path: db_dir)!

        let transactionStarted = DispatchSemaphore(value: 0)
        let closeCompleted = DispatchSemaphore(value: 0)
        var transactionResult: Pubkey? = nil
        let resultLock = NSLock()

        // Start transaction on background queue
        DispatchQueue.global().async {
            let result: Pubkey? = try? ndb.lookup_note(noteId) { maybeNote in
                // Signal that transaction has started
                transactionStarted.signal()
                // Hold the transaction open
                Thread.sleep(forTimeInterval: 0.1)
                switch maybeNote {
                case .none: return nil
                case .some(let note): return note.pubkey
                }
            }
            resultLock.lock()
            transactionResult = result
            resultLock.unlock()
        }

        // Wait for transaction to start (with timeout to avoid CI hangs)
        let startResult = transactionStarted.wait(timeout: .now() + 2.0)
        XCTAssertEqual(startResult, .success, "Transaction should start within timeout")
        guard startResult == .success else { return }

        // Now call close on another thread - it should wait for transaction
        DispatchQueue.global().async {
            ndb.close()
            closeCompleted.signal()
        }

        // Wait for close to complete (with timeout)
        let closeResult = closeCompleted.wait(timeout: .now() + 2.0)
        XCTAssertEqual(closeResult, .success, "Close should complete after transaction finishes")

        // Read result with synchronization
        resultLock.lock()
        let finalResult = transactionResult
        resultLock.unlock()
        XCTAssertEqual(finalResult, pk, "Transaction should have returned correct data")
    }

    /// Tests multiple transactions can be created and destroyed without crashes.
    ///
    /// Regression test for transaction retention mechanism under concurrent load.
    func test_multiple_concurrent_transactions() throws {
        let noteId = NoteId(hex: "d12c17bde3094ad32f4ab862a6cc6f5c289cfe7d5802270bdf34904df585f349")!
        let pk = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        // First: populate the database and close (flushes async writes)
        do {
            let ndb = Ndb(path: db_dir)!
            let ok = ndb.process_events(test_wire_events)
            XCTAssertTrue(ok)
        }

        // Second: reopen and test concurrent transaction behavior
        let ndb = Ndb(path: db_dir)!

        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        var successCount = 0
        let lock = NSLock()

        // Spawn multiple concurrent lookups
        for _ in 0..<10 {
            group.enter()
            queue.async {
                let result: Pubkey? = try? ndb.lookup_note(noteId) { maybeNote in
                    switch maybeNote {
                    case .none: return nil
                    case .some(let note): return note.pubkey
                    }
                }
                if result == pk {
                    lock.lock()
                    successCount += 1
                    lock.unlock()
                }
                group.leave()
            }
        }

        // Wait for all transactions to complete
        let waitResult = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(waitResult, .success, "All transactions should complete")
        XCTAssertEqual(successCount, 10, "All 10 lookups should succeed with correct data")

        ndb.close()
    }

    /// Tests that SafeNdbTxn.new cleans up properly when valueGetter returns nil.
    ///
    /// Verifies no retain leak: close() should complete even after valueGetter returns nil.
    func test_safe_txn_cleanup_on_nil_value() throws {
        // First: populate the database and close (flushes async writes)
        do {
            let ndb = Ndb(path: db_dir)!
            let ok = ndb.process_events(test_wire_events)
            XCTAssertTrue(ok)
        }

        // Second: reopen and test cleanup when valueGetter returns nil
        let ndb = Ndb(path: db_dir)!

        // Create a SafeNdbTxn where valueGetter returns nil
        let result: SafeNdbTxn<String>? = SafeNdbTxn.new(on: ndb, with: { _ in
            // Simulate valueGetter returning nil (e.g., lookup failed)
            return nil
        }, name: "nil_value_test")

        XCTAssertNil(result, "SafeNdbTxn should be nil when valueGetter returns nil")

        // The critical test: close() should complete without blocking
        // If cleanup failed, close() would deadlock waiting for the leaked retain
        let closeCompleted = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            ndb.close()
            closeCompleted.signal()
        }

        let closeResult = closeCompleted.wait(timeout: .now() + 2.0)
        XCTAssertEqual(closeResult, .success, "close() should complete - no retain leak")
    }

}

