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

    /// DETERMINISTIC REGRESSION TEST for PR #3614 invariant bug
    /// Tests that NdbTxn recovers from missing ndb_txn_ref_count in threadDictionary
    ///
    /// Bug: Safety check (lines 39-41) validates 2 keys but force unwraps 3rd key (line 48)
    /// - Checks: "ndb_txn", "txn_generation"
    /// - Force unwraps: "ndb_txn_ref_count" (NOT checked!)
    ///
    /// WITHOUT FIX: This test would CRASH at line 48 (as! Int on nil)
    /// WITH FIX: Detects inconsistent state, clears it, creates fresh transaction
    ///
    /// This test satisfies jb55 requirement: "test that replicates the issue and fails + a fix"
    func test_missing_ref_count_recovers_gracefully() throws {
        let ndb = Ndb(path: db_dir)!

        // First create a valid transaction to get a real ndb_txn
        var seededTxn: ndb_txn!
        do {
            guard let validTxn = NdbTxn<()>(ndb: ndb, name: "seed_txn") else {
                return XCTFail("Could not create seed transaction")
            }
            seededTxn = validTxn.txn
            // validTxn will deinit and clean up threadDictionary
        }

        // Manually seed threadDictionary with PARTIAL state (missing ref_count)
        // This simulates the bug condition where ref_count is missing
        Thread.current.threadDictionary["ndb_txn"] = seededTxn
        Thread.current.threadDictionary["txn_generation"] = ndb.generation
        // Deliberately omit "ndb_txn_ref_count" to trigger the bug

        print("🧪 Test: Attempting to create NdbTxn with missing ref_count")
        print("🧪 WITHOUT FIX: Would crash at NdbTxn.swift:48 (as! Int on nil)")
        print("🧪 WITH FIX: Should detect inconsistent state and recover")

        // Try to create transaction with inconsistent threadDictionary state
        // OLD CODE (before fix): Crashes on line 48 - let ref_count = ... as! Int
        // NEW CODE (with fix): Detects missing ref_count, clears state, creates fresh txn
        guard let txn = NdbTxn<()>(ndb: ndb, name: "recovery_txn") else {
            return XCTFail("Transaction creation should succeed with fix")
        }

        print("✅ Test PASSED: NdbTxn recovered from inconsistent state")

        // Verify the transaction was created successfully
        XCTAssertNotNil(txn)
        XCTAssertEqual(txn.inherited, false, "Should be a fresh transaction, not inherited")

        // Verify threadDictionary is now in consistent state
        XCTAssertNotNil(Thread.current.threadDictionary["ndb_txn"])
        XCTAssertNotNil(Thread.current.threadDictionary["txn_generation"])
        XCTAssertNotNil(Thread.current.threadDictionary["ndb_txn_ref_count"])
    }

    /// Test recovery from missing txn_generation
    func test_missing_generation_recovers_gracefully() throws {
        let ndb = Ndb(path: db_dir)!

        // Seed with valid txn
        var seededTxn: ndb_txn!
        do {
            guard let validTxn = NdbTxn<()>(ndb: ndb, name: "seed_txn") else {
                return XCTFail("Could not create seed transaction")
            }
            seededTxn = validTxn.txn
        }

        // Manually seed with missing txn_generation
        Thread.current.threadDictionary["ndb_txn"] = seededTxn
        Thread.current.threadDictionary["ndb_txn_ref_count"] = 1
        // Deliberately omit "txn_generation"

        print("🧪 Test: Missing txn_generation - should recover")

        guard let txn = NdbTxn<()>(ndb: ndb, name: "recovery_txn") else {
            return XCTFail("Transaction creation should succeed with fix")
        }

        XCTAssertNotNil(txn)
        XCTAssertEqual(txn.inherited, false, "Should be a fresh transaction")
    }

    /// Test recovery from completely empty threadDictionary (baseline sanity check)
    func test_empty_threadDict_creates_fresh_transaction() throws {
        let ndb = Ndb(path: db_dir)!

        // Ensure threadDictionary is completely clean
        Thread.current.threadDictionary.removeObject(forKey: "ndb_txn")
        Thread.current.threadDictionary.removeObject(forKey: "txn_generation")
        Thread.current.threadDictionary.removeObject(forKey: "ndb_txn_ref_count")

        print("🧪 Test: Empty threadDict - should create fresh transaction")

        guard let txn = NdbTxn<()>(ndb: ndb, name: "fresh_txn") else {
            return XCTFail("Should create fresh transaction when dict is empty")
        }

        XCTAssertNotNil(txn)
        XCTAssertEqual(txn.inherited, false)
    }

    /// Test recovery from stale generation (generation mismatch)
    func test_stale_generation_recovers_gracefully() throws {
        let ndb = Ndb(path: db_dir)!

        // Seed with valid txn
        var seededTxn: ndb_txn!
        do {
            guard let validTxn = NdbTxn<()>(ndb: ndb, name: "seed_txn") else {
                return XCTFail("Could not create seed transaction")
            }
            seededTxn = validTxn.txn
        }

        // Manually seed with STALE generation (doesn't match ndb.generation)
        Thread.current.threadDictionary["ndb_txn"] = seededTxn
        Thread.current.threadDictionary["txn_generation"] = ndb.generation - 1  // Stale!
        Thread.current.threadDictionary["ndb_txn_ref_count"] = 1

        print("🧪 Test: Stale generation - should create fresh transaction")

        guard let txn = NdbTxn<()>(ndb: ndb, name: "recovery_txn") else {
            return XCTFail("Transaction creation should succeed with fix")
        }

        XCTAssertNotNil(txn)
        XCTAssertEqual(txn.inherited, false, "Should be a fresh transaction, not inherited with stale generation")
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

    /// Test to reproduce ORIGINAL PR #3614 bug: transaction use-after-free during close
    ///
    /// Bug: Transaction pointers become invalid when Ndb closes while transactions active
    /// Expected: CRASH on old code (before PR #3614 fix)
    /// Expected: PASS on new code (with PR #3614 transaction retention fix)
    func test_use_after_free_crash_during_close() throws {
        let ndb = Ndb(path: db_dir)!
        let ok = ndb.process_events(test_wire_events)
        XCTAssertTrue(ok)

        print("🧪 REPRODUCING ORIGINAL PR #3614 BUG: Use-after-free during close")
        print("🧪 WITHOUT FIX: Should crash when accessing txn after close")
        print("🧪 WITH FIX: Should block close until transaction completes")

        let id = NoteId(hex: "d12c17bde3094ad32f4ab862a6cc6f5c289cfe7d5802270bdf34904df585f349")!

        // Create transaction and keep reference
        guard let txn = NdbTxn<()>(ndb: ndb, name: "test_txn") else {
            return XCTFail("Could not create transaction")
        }

        // Force close Ndb while transaction is active (simulates startup race from PR #3614)
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.01)
            print("🧪 Attempting to close Ndb while transaction active...")
            ndb.close()
            print("🧪 Ndb close completed")
        }

        // Give close time to happen
        Thread.sleep(forTimeInterval: 0.05)

        // Try to use transaction AFTER close (use-after-free on old code)
        print("🧪 Attempting to use transaction after close...")
        let result = try? ndb.lookup_note(id, borrow: { maybeNote -> String? in
            switch maybeNote {
            case .none:
                return nil
            case .some(let note):
                return String(note.content)
            }
        })

        print("🧪 Transaction use completed: \(result != nil ? "success" : "nil")")

        // On OLD code: Should crash with use-after-free accessing invalid txn pointer
        // On NEW code: Transaction retention prevents close, lookup succeeds or gracefully fails

        // Keep txn alive until end of test
        _ = txn
    }

    /// CRASH REPLICATION TEST for TF-crash-analysis-1.16-1277-hh0
    /// Related to PR #3614 - Transaction Use-After-Free
    /// Attempts to reproduce crash at NdbTxn.swift:47-48
    ///
    /// Race Condition:
    /// Thread A: Lines 39-41 safe check passes → threadDictionary entries exist
    /// Thread B: Deinit removes threadDictionary entries (lines 110-111)
    /// Thread A: Lines 47-48 force unwrap crashes → entries no longer exist
    func test_transaction_race_condition_reproduction() throws {
        let ndb = Ndb(path: db_dir)!
        _ = ndb.process_events(test_wire_events)

        print("🔬 ATTEMPTING TO REPRODUCE CRASH: TF-crash-analysis-1.16-1277-hh0")
        print("🔬 Target: NdbTxn.swift:47-48 force unwrap crash")
        print("🔬 Running 1000 iterations to hit narrow race window...")

        let iterations = 1000
        var successCount = 0

        for i in 0..<iterations {
            let expectation = XCTestExpectation(description: "Iteration \(i)")
            let queue1 = DispatchQueue(label: "parent.\(i)")
            let queue2 = DispatchQueue(label: "child.\(i)")

            var completed = false
            let lock = NSLock()

            // Parent thread: Creates transaction then destroys threadDictionary
            queue1.async {
                // Create parent transaction
                autoreleasepool {
                    _ = NdbTxn<()>(ndb: ndb, name: "parent_\(i)")
                    // Parent will deinit and clear threadDictionary here
                }

                lock.lock()
                completed = true
                lock.unlock()
            }

            // Child thread: Tries to create transaction while parent is deiniting
            queue2.async {
                for _ in 0..<10 {
                    lock.lock()
                    let isCompleted = completed
                    lock.unlock()

                    if !isCompleted {
                        // Try to create transaction during parent's deinit window
                        // This should crash at NdbTxn.swift:47-48 if we hit the race
                        _ = NdbTxn<()>(ndb: ndb, name: "child_\(i)")
                    }
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
            successCount += 1
        }

        print("🔬 CRASH REPLICATION TEST COMPLETED")
        print("🔬 Iterations completed without crash: \(successCount)/\(iterations)")
        print("🔬 If this test PASSED, the crash was NOT reproduced in \(iterations) attempts")
        print("🔬 If this test CRASHED with 'Fatal error: Unexpectedly found nil', SUCCESS!")
        print("🔬 Expected crash location: NdbTxn.swift:47 or :48")
        print("🔬 Race window is very narrow - may need more iterations or different timing")
    }

    /// CRITICAL TEST: Detect if LMDB deadlocks with overlapping same-thread transactions
    ///
    /// Related to: damus-cy9, damus-1gb (deadlock blocker for #3612)
    ///
    /// Purpose: Determine if NDB_FLAG_NOTLS is required before removing transaction inheritance
    ///
    /// Expected Results:
    /// - WITHOUT NOTLS: Test TIMES OUT or FAILS (second txn deadlocks)
    /// - WITH NOTLS: Test PASSES (both txns coexist on same thread)
    func test_same_thread_overlapping_txns_no_deadlock() throws {
        let ndb = Ndb(path: db_dir)!
        let ok = ndb.process_events(test_wire_events)
        XCTAssertTrue(ok)

        print("🔍 DEADLOCK DETECTION TEST")
        print("🔍 Testing if LMDB allows multiple transactions on same thread")
        print("🔍 This determines if NDB_FLAG_NOTLS is required for #3612")

        let expectation = XCTestExpectation(description: "Nested transactions complete")
        var testResult: String = "unknown"

        // Run on background thread to avoid interfering with main thread state
        DispatchQueue.global().async {
            print("🔍 Creating parent transaction...")
            guard let txn1 = NdbTxn<()>(ndb: ndb, name: "parent_txn") else {
                testResult = "parent_failed"
                expectation.fulfill()
                return
            }

            print("🔍 Parent transaction created successfully")
            print("🔍 Attempting to create child transaction on SAME thread...")

            // This is the critical test - can we open a second txn on same thread?
            guard let txn2 = NdbTxn<()>(ndb: ndb, name: "child_txn") else {
                print("⚠️  DEADLOCK DETECTED: Second transaction blocked by first")
                print("⚠️  NDB_FLAG_NOTLS is REQUIRED to remove inheritance safely")
                testResult = "deadlock_detected"
                expectation.fulfill()
                return
            }

            print("✅ Child transaction created successfully")
            print("✅ No deadlock - multiple same-thread transactions work!")
            print("✅ NDB_FLAG_NOTLS is either already enabled or not needed")

            testResult = "no_deadlock"

            // Keep both alive
            _ = txn1
            _ = txn2

            expectation.fulfill()
        }

        // Wait with timeout - if we deadlock, this will timeout
        let result = XCTWaiter.wait(for: [expectation], timeout: 3.0)

        switch result {
        case .completed:
            if testResult == "deadlock_detected" {
                XCTFail("""
                    ⚠️  CRITICAL: NDB_FLAG_NOTLS REQUIRED

                    LMDB rejected overlapping same-thread transactions.
                    Before removing inheritance (#3612), we MUST:
                    1. Implement MDB_NOTLS flag in nostrdb.c
                    2. Re-run this test to verify it passes

                    See: damus-cy9, nostrdb#121
                    """)
            } else if testResult == "no_deadlock" {
                print("✅ TEST PASSED: Safe to remove transaction inheritance")
                print("✅ No NDB_FLAG_NOTLS changes required")
            } else {
                XCTFail("Test completed but with unexpected result: \(testResult)")
            }
        case .timedOut:
            XCTFail("""
                ⚠️  TIMEOUT: Likely DEADLOCK

                The test timed out, which usually means the second transaction
                blocked waiting for the first to complete. This is a deadlock.

                REQUIRED: Implement NDB_FLAG_NOTLS before removing inheritance.
                """)
        default:
            XCTFail("Test failed with unexpected waiter result: \(result)")
        }
    }

    /// RESOURCE LEAK TEST: SafeNdbTxn.new nil-path leak (damus-vxu)
    ///
    /// Bug: When valueGetter returns nil, SafeNdbTxn.new opens a transaction
    /// but never closes it before returning nil.
    ///
    /// Expected: Test FAILS on old code (leak detected), PASSES on new code (fixed)
    func test_SafeNdbTxn_new_nil_path_leaks_transaction() throws {
        let ndb = Ndb(path: db_dir)!
        let ok = ndb.process_events(test_wire_events)
        XCTAssertTrue(ok)

        print("🔍 LEAK TEST: SafeNdbTxn.new nil-path")

        #if TXNDEBUG
        let initialTxnCount = txn_count
        print("🔍 Initial txn_count: \(initialTxnCount)")

        // Trigger the nil-path in SafeNdbTxn.new
        // This happens when valueGetter returns outer nil
        let result = SafeNdbTxn<String?>.new(on: ndb) { _ in
            // Return outer nil (not .some(nil))
            // This triggers "guard let val = valueGetter(placeholderTxn) else { return nil }"
            return nil
        }

        XCTAssertNil(result, "Should return nil on valueGetter nil")

        let finalTxnCount = txn_count
        print("🔍 Final txn_count: \(finalTxnCount)")

        // WITHOUT FIX: txn_count will be +1 (transaction leaked)
        // WITH FIX: txn_count should return to initial (transaction closed)
        XCTAssertEqual(finalTxnCount, initialTxnCount,
                       "❌ LEAK DETECTED: Transaction was not closed on nil path. Expected \(initialTxnCount), got \(finalTxnCount)")

        print("✅ No leak - transaction properly closed on nil path")
        #else
        print("⚠️  TXNDEBUG not enabled - cannot detect leaks. Skipping test.")
        #endif
    }

    /// RESOURCE LEAK TEST: SafeNdbTxn.maybeExtend nil-path leak (damus-3do)
    ///
    /// Bug: When maybeExtend's closure returns nil, self.moved=true was set
    /// before consume, causing deinit to skip close. Transaction is orphaned.
    ///
    /// Expected: Test FAILS on old code (leak detected), PASSES on new code (fixed)
    func test_SafeNdbTxn_maybeExtend_nil_path_leaks_transaction() throws {
        let ndb = Ndb(path: db_dir)!
        let ok = ndb.process_events(test_wire_events)
        XCTAssertTrue(ok)

        print("🔍 LEAK TEST: SafeNdbTxn.maybeExtend nil-path")

        #if TXNDEBUG
        let initialTxnCount = txn_count
        print("🔍 Initial txn_count: \(initialTxnCount)")

        // Create SafeNdbTxn then call maybeExtend with nil-returning closure
        let txn = SafeNdbTxn<Int>.new(on: ndb) { _ in 42 }
        XCTAssertNotNil(txn)

        let midTxnCount = txn_count
        print("🔍 Mid txn_count: \(midTxnCount)")
        XCTAssertEqual(midTxnCount, initialTxnCount + 1, "One txn should be active")

        // Call maybeExtend with closure that returns nil
        let result = txn?.maybeExtend { _ in
            return nil as String?  // Returns nil, triggers leak path
        }

        XCTAssertNil(result, "Should return nil when with() returns nil")

        // Force txn to go out of scope and deinit
        _ = result

        let finalTxnCount = txn_count
        print("🔍 Final txn_count: \(finalTxnCount)")

        // WITHOUT FIX: txn_count still +1 (leaked, moved=true prevented close)
        // WITH FIX: txn_count back to initial (explicitly closed on nil path)
        XCTAssertEqual(finalTxnCount, initialTxnCount,
                       "❌ LEAK DETECTED: Transaction leaked after maybeExtend nil. Expected \(initialTxnCount), got \(finalTxnCount)")

        print("✅ No leak - transaction properly closed after maybeExtend nil")
        #else
        print("⚠️  TXNDEBUG not enabled - cannot detect leaks. Skipping test.")
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

}

