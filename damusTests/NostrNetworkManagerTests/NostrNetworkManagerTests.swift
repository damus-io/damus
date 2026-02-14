//
//  NostrNetworkManagerTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2025-08-22.
//

import XCTest
@testable import damus


@MainActor
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
                        if let note = try? ndb.lookup_note_by_key_and_copy(noteKey) {
                            count += 1
                            receivedIds.insert(note.id)
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

    /// Ensures the relay list listener ignores a bad event and still applies the next valid update.
    func testRelayListListenerSkipsInvalidEventsAndContinues() async throws {
        let ndb = Ndb.test
        let delegate = MockNetworkDelegate(ndb: ndb, keypair: test_keypair, bootstrapRelays: [RelayURL("wss://relay.damus.io")!])
        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let reader = MockSubscriptionManager(pool: pool, ndb: ndb)
        let manager = SpyUserRelayListManager(delegate: delegate, pool: pool, reader: reader)
        let appliedExpectation = expectation(description: "Applies valid relay list after encountering an invalid event")
        manager.setExpectation = appliedExpectation

        guard let invalidEvent = NostrEvent(content: "invalid", keypair: test_keypair, kind: NostrKind.metadata.rawValue, createdAt: 1) else {
            XCTFail("Failed to create invalid test event")
            return
        }
        let validRelayList = NIP65.RelayList(relays: [RelayURL("wss://relay-2.damus.io")!])
        guard let validEvent = validRelayList.toNostrEvent(keypair: test_keypair_full) else {
            XCTFail("Failed to create valid relay list event")
            return
        }

        // Feed the listener a bad event followed by a valid relay list.
        reader.queuedLenders = [.owned(invalidEvent), .owned(validEvent)]

        await manager.listenAndHandleRelayUpdates()
        await fulfillment(of: [appliedExpectation], timeout: 1.0)

        XCTAssertEqual(manager.setCallCount, 1)
        XCTAssertEqual(manager.appliedRelayLists.first?.relays.count, validRelayList.relays.count)
    }

    /// Ensures duplicate relay list events with the same created_at are deduplicated.
    ///
    /// Regression test for PR #3542: When the same relay list event arrives from multiple
    /// relays simultaneously, only the first should be processed. Before the fix,
    /// an async DB lookup created a race window where both events passed the created_at guard.
    func testRelayListListenerDeduplicatesSameTimestampEvents() async throws {
        let ndb = Ndb.test
        let delegate = MockNetworkDelegate(ndb: ndb, keypair: test_keypair, bootstrapRelays: [RelayURL("wss://relay.damus.io")!])
        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let reader = MockSubscriptionManager(pool: pool, ndb: ndb)
        let manager = SpyUserRelayListManager(delegate: delegate, pool: pool, reader: reader)
        let appliedExpectation = expectation(description: "At least one relay list should be applied")
        manager.setExpectation = appliedExpectation

        let timestamp: UInt32 = 1000

        let relayList1 = NIP65.RelayList(relays: [RelayURL("wss://relay-1.damus.io")!])
        guard let event1 = relayList1.toNostrEvent(keypair: test_keypair_full, timestamp: timestamp) else {
            XCTFail("Failed to create relay list event 1")
            return
        }

        let relayList2 = NIP65.RelayList(relays: [RelayURL("wss://relay-2.damus.io")!])
        guard let event2 = relayList2.toNostrEvent(keypair: test_keypair_full, timestamp: timestamp) else {
            XCTFail("Failed to create relay list event 2")
            return
        }

        // Simulate the same relay list event arriving from two different relays
        reader.queuedLenders = [.owned(event1), .owned(event2)]

        await manager.listenAndHandleRelayUpdates()
        await fulfillment(of: [appliedExpectation], timeout: 1.0)

        // With the fix: only the first event is processed (local timestamp dedup)
        // Before the fix: both pass (async DB lookup returns nil/0 each time)
        XCTAssertEqual(manager.setCallCount, 1, "Duplicate relay list events with same created_at should be deduplicated")
    }

    /// Ensures @Published property updates from disconnect() arrive on the main thread.
    ///
    /// Regression test for PR #3542: RelayConnection's @Published properties (isConnected,
    /// isConnecting) must be updated on the main thread for Combine/SwiftUI safety.
    /// Before the fix, calling disconnect() from a background thread set them directly
    /// on that thread, causing undefined behavior and UI freezes.
    func testRelayConnectionDisconnectUpdatesStateOnMainThread() async throws {
        let url = RelayURL("wss://relay.damus.io")!
        let connection = RelayConnection(
            url: url,
            handleEvent: { _ in },
            processUnverifiedWSEvent: { _ in }
        )

        let mainThreadExpectation = expectation(description: "isConnected update should arrive on main thread")

        let cancellable = connection.$isConnected
            .dropFirst() // Skip initial value
            .sink { _ in
                XCTAssertTrue(Thread.isMainThread, "isConnected was updated off the main thread")
                mainThreadExpectation.fulfill()
            }

        // Call disconnect from a background thread to trigger the bug
        DispatchQueue.global(qos: .userInitiated).async {
            connection.disconnect()
        }

        await fulfillment(of: [mainThreadExpectation], timeout: 2.0)
        cancellable.cancel()
    }

}

// MARK: - Test doubles

private final class MockNetworkDelegate: NostrNetworkManager.Delegate {
    var ndb: Ndb
    var keypair: Keypair
    var latestRelayListEventIdHex: String?
    var latestContactListEvent: NostrEvent?
    var bootstrapRelays: [RelayURL]
    var developerMode: Bool = false
    var experimentalLocalRelayModelSupport: Bool = false
    var relayModelCache: RelayModelCache
    var relayFilters: RelayFilters
    var nwcWallet: WalletConnectURL?

    init(ndb: Ndb, keypair: Keypair, bootstrapRelays: [RelayURL]) {
        self.ndb = ndb
        self.keypair = keypair
        self.bootstrapRelays = bootstrapRelays
        self.relayModelCache = RelayModelCache()
        self.relayFilters = RelayFilters(our_pubkey: keypair.pubkey)
    }
}

private final class MockSubscriptionManager: NostrNetworkManager.SubscriptionManager {
    var queuedLenders: [NdbNoteLender] = []

    init(pool: RelayPool, ndb: Ndb) {
        super.init(pool: pool, ndb: ndb, experimentalLocalRelayModelSupport: false)
    }

    override func streamIndefinitely(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, streamMode: NostrNetworkManager.StreamMode? = nil, preloadStrategy: NostrNetworkManager.PreloadStrategy? = nil, id: UUID? = nil) -> AsyncStream<NdbNoteLender> {
        let lenders = queuedLenders
        return AsyncStream { continuation in
            lenders.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

private final class SpyUserRelayListManager: NostrNetworkManager.UserRelayListManager {
    var setCallCount = 0
    var appliedRelayLists: [NIP65.RelayList] = []
    var setExpectation: XCTestExpectation?

    override func set(userRelayList: NIP65.RelayList) async throws(UpdateError) {
        setCallCount += 1
        appliedRelayLists.append(userRelayList)
        setExpectation?.fulfill()
    }
}
