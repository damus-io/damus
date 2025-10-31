//
//  NostrNetworkManagerTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2025-08-22.
//

import XCTest
@testable import damus


class NostrNetworkManagerTests: XCTestCase {
    var damusState: DamusState? = nil
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        damusState = generate_test_damus_state(
            mock_profile_info: nil,
            addNdbToRelayPool: false    // Don't give RelayPool any access to Ndb. This will prevent incoming notes from affecting our test
        )

        let notesJSONL = getTestNotesJSONL()

        for noteText in notesJSONL.split(separator: "\n") {
            let _ = damusState!.ndb.processEvent("[\"EVENT\",\"subid\",\(String(noteText))]")
        }
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        damusState = nil
    }
    
    func getTestNotesJSONL() -> String {
        // Get the path for the test_notes.jsonl file in the same folder as this test file
        let testBundle = Bundle(for: type(of: self))
        let fileURL = testBundle.url(forResource: "test_notes", withExtension: "jsonl")!

        // Load the contents of the file
        return try! String(contentsOf: fileURL, encoding: .utf8)
    }
    
    func ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter, expectedCount: Int) async {
        let endOfStream = XCTestExpectation(description: "Stream should receive EOSE")
        let atLeastXEvents = XCTestExpectation(description: "Stream should get at least the expected number of notes")
        var receivedCount = 0
        var eventIds: Set<NoteId> = []
        Task {
            for await item in self.damusState!.nostrNetwork.reader.advancedStream(filters: [filter], streamMode: .ndbOnly) {
                switch item {
                case .event(let lender):
                    try? lender.borrow { event in
                        receivedCount += 1
                        if eventIds.contains(event.id) {
                            XCTFail("Got duplicate event ID: \(event.id) ")
                        }
                        eventIds.insert(event.id)
                    }
                    if eventIds.count >= expectedCount {
                        atLeastXEvents.fulfill()
                    }
                case .eose:
                    continue
                case .ndbEose:
                    // End of stream, break out of the loop
                    endOfStream.fulfill()
                    continue
                case .networkEose:
                    continue
                }
            }
        }
        await fulfillment(of: [endOfStream, atLeastXEvents], timeout: 15.0)
        XCTAssertEqual(receivedCount, expectedCount, "Event IDs: \(eventIds.map({ $0.hex() }))")
    }
    
    /// Tests to ensure that subscribing gets the correct amount of events
    ///
    /// ## Implementation notes:
    ///
    /// To create a new scenario, `nak` can be used as a reference:
    /// 1. `cd` into the folder where the `test_notes.jsonl` file is
    /// 2. Run `nak serve --events test_notes.jsonl`
    /// 3. On a separate terminal, run `nak` commands with the desired filter against the local relay, and get the line count. Example:
    /// ```
    /// nak req --kind 1 ws://localhost:10547 | wc -l
    /// ```
    func testNdbSubscription() async {
        await ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(kinds: [.text]), expectedCount: 57)
        await ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(authors: [Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!]), expectedCount: 22)
        await ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(kinds: [.boost], referenced_ids: [NoteId(hex: "64b26d0a587f5f894470e1e4783756b4d8ba971226de975ee30ac1b69970d5a1")!]), expectedCount: 5)
        await ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(kinds: [.text, .boost, .zap], referenced_ids: [NoteId(hex: "64b26d0a587f5f894470e1e4783756b4d8ba971226de975ee30ac1b69970d5a1")!], limit: 500), expectedCount: 5)
        await ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(kinds: [.text], limit: 10), expectedCount: 10)
        await ensureSubscribeGetsAllExpectedNotes(filter: NostrFilter(kinds: [.text], until: UInt32(Date.now.timeIntervalSince1970), limit: 10), expectedCount: 10)
    }
    
    /// Tests Ndb streaming directly without NostrNetworkManager
    ///
    /// This test verifies that Ndb's subscription mechanism reliably returns all stored events
    /// without any intermittent failures. The test creates a fresh Ndb instance, populates it
    /// with a known number of events, subscribes to them, and verifies the count matches exactly.
    func testDirectNdbStreaming() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }
        
        // Pre-populate database with 100 test notes
        let expectedCount = 100
        let testPubkey = test_keypair_full.pubkey
        
        for i in 0..<expectedCount {
            let testNote = NostrEvent(
                content: "Test note \(i)",
                keypair: test_keypair,
                kind: NostrKind.text.rawValue,
                tags: []
            )
            
            // Process the event as a relay message
            let eventJson = encode_json(testNote)!
            let relayMessage = "[\"EVENT\",\"subid\",\(eventJson)]"
            let processed = ndb.processEvent(relayMessage)
            XCTAssertTrue(processed, "Failed to process event \(i)")
        }
        
        // Give Ndb a moment to finish processing all events
        try await Task.sleep(for: .milliseconds(100))
        
        // Subscribe and count all events
        var count = 0
        var receivedIds = Set<NoteId>()
        let subscribeExpectation = XCTestExpectation(description: "Should receive all events and EOSE")
        let atLeastXNotes = XCTestExpectation(description: "Should get at least the expected amount of notes")
        
        Task {
            do {
                for try await item in try ndb.subscribe(filters: [NostrFilter(kinds: [.text], authors: [testPubkey])]) {
                    switch item {
                    case .event(let noteKey):
                        // Lookup the note to verify it exists
                        if let txn = NdbTxn(ndb: ndb) {
                            if let note = ndb.lookup_note_by_key_with_txn(noteKey, txn: txn) {
                                count += 1
                                receivedIds.insert(note.id)
                            }
                        }
                        if count >= expectedCount {
                            atLeastXNotes.fulfill()
                        }
                    case .eose:
                        // End of stored events
                        subscribeExpectation.fulfill()
                        break
                    }
                }
            } catch {
                XCTFail("Subscription failed with error: \(error)")
            }
        }
        
        await fulfillment(of: [subscribeExpectation, atLeastXNotes], timeout: 10.0)
        
        // Verify we received exactly the expected number of unique events
        XCTAssertEqual(count, expectedCount, "Should receive all \(expectedCount) events")
        XCTAssertEqual(receivedIds.count, expectedCount, "Should receive \(expectedCount) unique events")
    }
}
