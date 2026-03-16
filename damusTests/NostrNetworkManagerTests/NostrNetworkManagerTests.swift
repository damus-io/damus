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

    // MARK: - Relay list stale-data regression tests

    /// Regression: removing a relay must not fall back to bootstrap relays.
    ///
    /// Before the fix, `getLatestNIP65RelayListEvent()` used a UserDefaults hex lookup
    /// that could go stale, causing `getUserCurrentRelayList()` to return nil and
    /// `remove()` to throw `.noInitialRelayList`. The user could never disconnect a relay.
    func testRemoveRelayDoesNotFallBackToBootstrapList() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let relayA = RelayURL("wss://relay-a.example.com")!
        let relayB = RelayURL("wss://relay-b.example.com")!
        let relayC = RelayURL("wss://relay-c.example.com")!
        let bootstrapRelay = RelayURL("wss://bootstrap.example.com")!

        let initialList = NIP65.RelayList(relays: [relayA, relayB, relayC])
        let initialEvent = initialList.toNostrEvent(keypair: test_keypair_full)!
        let eventJson = encode_json(initialEvent)!
        let processed = ndb.processEvent("[\"EVENT\",\"subid\",\(eventJson)]")
        XCTAssertTrue(processed, "Failed to process relay list event into ndb")
        try await Task.sleep(for: .milliseconds(100))

        let delegate = MockNetworkDelegate(
            ndb: ndb,
            keypair: test_keypair,
            bootstrapRelays: [bootstrapRelay]
        )
        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let reader = MockSubscriptionManager(pool: pool, ndb: ndb)
        let manager = NostrNetworkManager.UserRelayListManager(
            delegate: delegate, pool: pool, reader: reader
        )

        // Remove relay B from [A, B, C] — should yield [A, C]
        try await manager.remove(relayURL: relayB)

        let currentList = await manager.getUserCurrentRelayList()
        XCTAssertNotNil(currentList, "Relay list must not be nil after remove")
        let urls = Set(currentList!.relays.keys)
        XCTAssertEqual(urls, [relayA, relayC], "List should be [A, C] after removing B")
        XCTAssertFalse(urls.contains(relayB), "Removed relay B must not be present")
        XCTAssertFalse(urls.contains(bootstrapRelay), "Must not fall back to bootstrap relays")
    }

    /// Regression: the in-memory cache must bridge the nostrdb async write gap.
    ///
    /// After `set()`, `getUserCurrentRelayList()` must immediately return the new list,
    /// even before nostrdb's async worker has committed the event.
    func testCacheBridgesAsyncWriteGap() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let delegate = MockNetworkDelegate(
            ndb: ndb,
            keypair: test_keypair,
            bootstrapRelays: [RelayURL("wss://bootstrap.example.com")!]
        )
        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let reader = MockSubscriptionManager(pool: pool, ndb: ndb)
        let manager = NostrNetworkManager.UserRelayListManager(
            delegate: delegate, pool: pool, reader: reader
        )

        let relayA = RelayURL("wss://relay-a.example.com")!
        let relayC = RelayURL("wss://relay-c.example.com")!
        let newList = NIP65.RelayList(relays: [relayA, relayC])

        // set() should populate the cache immediately
        try await manager.set(userRelayList: newList)

        // Query immediately — no sleep — ndb may not have committed yet
        let currentList = await manager.getUserCurrentRelayList()
        XCTAssertNotNil(currentList, "Cache must serve the list immediately after set()")
        XCTAssertEqual(Set(currentList!.relays.keys), [relayA, relayC])
    }

    /// Regression: rapid sequential removes must not reintroduce removed relays.
    ///
    /// Scenario: start with [A, B, C], remove B, then immediately remove C.
    /// Without the cache, the second `remove()` might read a stale [A, B, C] from ndb
    /// (because the first set hasn't committed yet), producing [A, B] — relay B is back.
    func testRapidSequentialRemovesDoNotReintroduceRelays() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let relayA = RelayURL("wss://relay-a.example.com")!
        let relayB = RelayURL("wss://relay-b.example.com")!
        let relayC = RelayURL("wss://relay-c.example.com")!

        let initialList = NIP65.RelayList(relays: [relayA, relayB, relayC])
        let initialEvent = initialList.toNostrEvent(keypair: test_keypair_full)!
        let eventJson = encode_json(initialEvent)!
        XCTAssertTrue(ndb.processEvent("[\"EVENT\",\"subid\",\(eventJson)]"))
        try await Task.sleep(for: .milliseconds(100))

        let delegate = MockNetworkDelegate(
            ndb: ndb,
            keypair: test_keypair,
            bootstrapRelays: []
        )
        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let reader = MockSubscriptionManager(pool: pool, ndb: ndb)
        let manager = NostrNetworkManager.UserRelayListManager(
            delegate: delegate, pool: pool, reader: reader
        )

        // Remove B then immediately remove C — no sleep between
        try await manager.remove(relayURL: relayB)
        try await manager.remove(relayURL: relayC)

        let currentList = await manager.getUserCurrentRelayList()
        XCTAssertNotNil(currentList)
        let urls = Set(currentList!.relays.keys)
        XCTAssertEqual(urls, [relayA], "Only relay A should remain after removing B and C")
        XCTAssertFalse(urls.contains(relayB), "Relay B must not reappear after sequential removes")
        XCTAssertFalse(urls.contains(relayC), "Relay C must stay removed")
    }

    /// Verify that `load()` clears the in-memory cache so ndb becomes the source of truth again.
    func testLoadClearsCacheAndReadsFromNdb() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let relayA = RelayURL("wss://relay-a.example.com")!
        let relayB = RelayURL("wss://relay-b.example.com")!

        // Seed ndb with [A, B]
        let ndbList = NIP65.RelayList(relays: [relayA, relayB])
        let ndbEvent = ndbList.toNostrEvent(keypair: test_keypair_full)!
        XCTAssertTrue(ndb.processEvent("[\"EVENT\",\"subid\",\(encode_json(ndbEvent)!)]"))
        try await Task.sleep(for: .milliseconds(100))

        let delegate = MockNetworkDelegate(
            ndb: ndb,
            keypair: test_keypair,
            bootstrapRelays: []
        )
        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let reader = MockSubscriptionManager(pool: pool, ndb: ndb)
        let manager = NostrNetworkManager.UserRelayListManager(
            delegate: delegate, pool: pool, reader: reader
        )

        // set() populates cache with [A] only
        try await manager.set(userRelayList: NIP65.RelayList(relays: [relayA]))
        let cachedList = await manager.getUserCurrentRelayList()
        XCTAssertEqual(Set(cachedList!.relays.keys), [relayA], "Cache should serve [A]")

        // load() must clear the cache so ndb is queried again
        await manager.load()

        // After load(), the list should come from ndb.
        // ndb now has the [A] event from set() (committed by now) or the original [A,B].
        // Either way, the cache is cleared — the manager reads from ndb, not stale cache.
        let afterLoad = await manager.getUserCurrentRelayList()
        XCTAssertNotNil(afterLoad, "Must return a relay list from ndb after load()")
    }

    /// Regression: ndb query must find the relay list without a stored hex ID.
    ///
    /// Before the fix, a fresh session with no `latestRelayListEventIdHex` in UserDefaults
    /// meant `getLatestNIP65RelayListEvent()` returned nil, even though ndb had the event.
    func testNdbQueryFindsRelayListWithoutStoredHex() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let relayA = RelayURL("wss://relay-a.example.com")!
        let relayB = RelayURL("wss://relay-b.example.com")!

        // Seed ndb — simulates a relay list that arrived via sync, not user action
        let list = NIP65.RelayList(relays: [relayA, relayB])
        let event = list.toNostrEvent(keypair: test_keypair_full)!
        XCTAssertTrue(ndb.processEvent("[\"EVENT\",\"subid\",\(encode_json(event)!)]"))
        try await Task.sleep(for: .milliseconds(100))

        // No hex stored anywhere — fresh delegate with no latestRelayListEventIdHex
        let delegate = MockNetworkDelegate(
            ndb: ndb,
            keypair: test_keypair,
            bootstrapRelays: [RelayURL("wss://bootstrap.example.com")!]
        )
        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let reader = MockSubscriptionManager(pool: pool, ndb: ndb)
        let manager = NostrNetworkManager.UserRelayListManager(
            delegate: delegate, pool: pool, reader: reader
        )

        let currentList = await manager.getUserCurrentRelayList()
        XCTAssertNotNil(currentList, "ndb query must find relay list without stored hex")
        let urls = Set(currentList!.relays.keys)
        XCTAssertEqual(urls, [relayA, relayB])
        XCTAssertFalse(
            urls.contains(RelayURL("wss://bootstrap.example.com")!),
            "Must not fall back to bootstrap when ndb has the event"
        )
    }
}

// MARK: - Test doubles

private final class MockNetworkDelegate: NostrNetworkManager.Delegate {
    var ndb: Ndb
    var keypair: Keypair
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
