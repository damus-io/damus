//
//  SpinnerFixTests.swift
//  damusTests
//
//  Tests for issue #3498 - infinite spinner on quoted notes
//
//  These tests exercise actual production code to verify:
//  1. SubscriptionManager doesn't hang when no relays are connected (ensureConnected fix)
//  2. NDB fast path returns events immediately
//  3. Handler injection proves guard continue fix
//

import XCTest
@testable import damus

/// Tests for issue #3498: infinite spinner on quoted notes.
///
/// Verifies fixes for RelayPool subscription handling where concurrent subscriptions
/// would terminate prematurely due to a `return` instead of `continue` in the sub_id
/// guard statement.
///
/// Key tests:
/// - `testSubscriptionContinuesAfterMismatchedSubId`: Proves the core `return` → `continue` fix
/// - `testInterleavedSubscriptionsReceiveCorrectEvents`: Proves concurrent subscriptions don't interfere
/// - `testLookupReturnsNilWhenNoRelaysConnected`: Proves the `ensureConnected` fix
///
/// Uses DEBUG test hooks (`injectTestEvent`, `testableHandlerSubIds`) to inject events
/// directly into RelayPool handlers, testing the consumer-side filtering logic without
/// network dependencies.
@MainActor
final class SpinnerFixTests: XCTestCase {

    // MARK: - Helper: Wait for handler registration

    /// Polls until the expected number of handlers are registered, with timeout.
    /// Avoids flaky fixed sleeps on slow CI.
    private func waitForHandlers(pool: RelayPool, count: Int, timeout: Duration = .seconds(2)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let currentCount = await pool.testableHandlerSubIds.count
            if currentCount >= count { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(count) handlers (have \(await pool.testableHandlerSubIds.count))")
    }

    // MARK: - Test: ensureConnected prevents hanging (Key bug fix)

    /// Verifies that when no relays are connected, lookup returns nil
    /// rather than hanging indefinitely waiting for a response.
    ///
    /// Before fix: Would hang forever waiting for relay responses
    /// After fix: Returns nil when ensureConnected returns empty
    func testLookupReturnsNilWhenNoRelaysConnected() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let reader = NostrNetworkManager.SubscriptionManager(
            pool: pool,
            ndb: ndb,
            experimentalLocalRelayModelSupport: false
        )

        // Event ID that doesn't exist in NDB
        let fakeNoteId = NoteId(Data(repeating: 0xAB, count: 32))

        // Lookup should return nil since:
        // 1. Event not in NDB
        // 2. No relays connected -> ensureConnected returns empty -> return nil
        let result = try await reader.lookup(noteId: fakeNoteId, timeout: .seconds(3))

        XCTAssertNil(result, "Should return nil when no relays connected and event not in NDB")
        // Note: We don't assert timing - just that it completes without hanging
    }

    // MARK: - Test: NDB fast path works

    /// Verifies that looking up an event that exists in NDB returns it
    /// without network calls.
    ///
    /// This is the "happy path" - spinner should never appear if event is cached.
    func testLookupReturnsEventFromNdb() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let testEvent = NostrEvent(
            content: "Test event for NDB lookup",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        // Store event in NDB first
        _ = ndb.processEvent("[\"EVENT\",\"test\",\(encode_json(testEvent)!)]")
        try await Task.sleep(for: .milliseconds(50))

        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let reader = NostrNetworkManager.SubscriptionManager(
            pool: pool,
            ndb: ndb,
            experimentalLocalRelayModelSupport: false
        )

        // Lookup should find it in NDB
        let lender = try await reader.lookup(noteId: testEvent.id)

        XCTAssertNotNil(lender, "Should find event in NDB")

        var foundEvent: NostrEvent?
        lender?.justUseACopy { foundEvent = $0 }

        XCTAssertEqual(foundEvent?.id, testEvent.id, "Should return correct event")
        XCTAssertEqual(foundEvent?.content, testEvent.content, "Event content should match")
    }

    // MARK: - Test: Sequential lookups work correctly

    /// Tests that multiple sequential lookups to the same SubscriptionManager
    /// work correctly and don't interfere with each other.
    func testSequentialLookupsWorkCorrectly() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let event1 = NostrEvent(
            content: "Sequential test event 1",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        let event2 = NostrEvent(
            content: "Sequential test event 2",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        // Store both events
        _ = ndb.processEvent("[\"EVENT\",\"seq1\",\(encode_json(event1)!)]")
        _ = ndb.processEvent("[\"EVENT\",\"seq2\",\(encode_json(event2)!)]")
        try await Task.sleep(for: .milliseconds(50))

        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let reader = NostrNetworkManager.SubscriptionManager(
            pool: pool,
            ndb: ndb,
            experimentalLocalRelayModelSupport: false
        )

        // Sequential lookups
        let result1 = try await reader.lookup(noteId: event1.id)
        let result2 = try await reader.lookup(noteId: event2.id)

        XCTAssertNotNil(result1, "First lookup should succeed")
        XCTAssertNotNil(result2, "Second lookup should succeed")

        var found1: NostrEvent?
        var found2: NostrEvent?
        result1?.justUseACopy { found1 = $0 }
        result2?.justUseACopy { found2 = $0 }

        XCTAssertEqual(found1?.id, event1.id, "First lookup returns correct event")
        XCTAssertEqual(found2?.id, event2.id, "Second lookup returns correct event")
    }

    // MARK: - Test: Concurrent lookups work correctly

    /// Tests that multiple concurrent lookups to the same SubscriptionManager
    /// complete without deadlock or interference.
    func testConcurrentLookupsWorkCorrectly() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let event1 = NostrEvent(
            content: "Concurrent test event 1",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        let event2 = NostrEvent(
            content: "Concurrent test event 2",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        // Store both events
        _ = ndb.processEvent("[\"EVENT\",\"con1\",\(encode_json(event1)!)]")
        _ = ndb.processEvent("[\"EVENT\",\"con2\",\(encode_json(event2)!)]")
        try await Task.sleep(for: .milliseconds(50))

        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let reader = NostrNetworkManager.SubscriptionManager(
            pool: pool,
            ndb: ndb,
            experimentalLocalRelayModelSupport: false
        )

        // Concurrent lookups
        async let lookup1 = reader.lookup(noteId: event1.id)
        async let lookup2 = reader.lookup(noteId: event2.id)

        let (result1, result2) = try await (lookup1, lookup2)

        XCTAssertNotNil(result1, "First concurrent lookup should succeed")
        XCTAssertNotNil(result2, "Second concurrent lookup should succeed")

        var found1: NostrEvent?
        var found2: NostrEvent?
        result1?.justUseACopy { found1 = $0 }
        result2?.justUseACopy { found2 = $0 }

        XCTAssertEqual(found1?.id, event1.id, "First lookup returns correct event")
        XCTAssertEqual(found2?.id, event2.id, "Second lookup returns correct event")
    }

    // MARK: - Test: Subscription completes via EOSE timeout (no-hang verification)

    /// Verifies that RelayPool subscriptions complete via EOSE timeout
    /// when no relays are connected, rather than hanging indefinitely.
    ///
    /// NOTE: This test verifies the "no hang" behavior only. It does not
    /// assert event delivery since that depends on NDB timing.
    func testSubscriptionCompletesViaEoseTimeout_NoHang() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let pool = RelayPool(ndb: ndb, keypair: test_keypair)

        let testEvent = NostrEvent(
            content: "Test event for EOSE",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        _ = ndb.processEvent("[\"EVENT\",\"eose\",\(encode_json(testEvent)!)]")
        try await Task.sleep(for: .milliseconds(50))

        let eoseReceived = XCTestExpectation(description: "EOSE received (timeout path)")

        let task = Task {
            let filter = NostrFilter(ids: [testEvent.id])
            for await item in await pool.subscribe(filters: [filter], eoseTimeout: .seconds(1)) {
                if case .eose = item {
                    eoseReceived.fulfill()
                    return
                }
            }
        }

        await fulfillment(of: [eoseReceived], timeout: 3.0)
        task.cancel()
    }

    // MARK: - Test: Handler injection proves guard continue fix (CORE TEST)

    /// **This is the key test for the `return` → `continue` fix at RelayPool.swift:531**
    ///
    /// Tests that when a subscription receives an event with a mismatched sub_id,
    /// it skips that event and continues processing subsequent events.
    ///
    /// - Old behavior (`return`): Stream would terminate on mismatched sub_id
    /// - New behavior (`continue`): Stream skips mismatched, continues processing
    ///
    /// This test:
    /// 1. Starts a subscription (registers handler with sub_id)
    /// 2. Injects event with WRONG sub_id (should be skipped)
    /// 3. Injects event with CORRECT sub_id (should be received)
    /// 4. Asserts the correct event is received (proves `continue` works)
    func testSubscriptionContinuesAfterMismatchedSubId() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let testRelay = RelayURL("wss://test.relay.example")!

        // Create test event
        let targetEvent = NostrEvent(
            content: "Target event that should be received",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        let initialHandlerCount = await pool.testableHandlerSubIds.count
        var receivedEvents: [NoteId] = []
        let eventReceived = XCTestExpectation(description: "Should receive target event")

        // Start subscription - this registers a handler
        let subscriptionTask = Task {
            let filter = NostrFilter(ids: [targetEvent.id])
            for await item in await pool.subscribe(filters: [filter], eoseTimeout: .seconds(5)) {
                switch item {
                case .event(let event):
                    receivedEvents.append(event.id)
                    if event.id == targetEvent.id {
                        eventReceived.fulfill()
                    }
                case .eose:
                    break
                }
            }
        }

        // Wait for handler registration (polling, not fixed sleep)
        try await waitForHandlers(pool: pool, count: initialHandlerCount + 1)

        // Get the actual sub_id from the registered handler
        // Note: handlers are appended, so last is most recent
        let subIds = await pool.testableHandlerSubIds
        guard let actualSubId = subIds.last else {
            XCTFail("No handler registered")
            subscriptionTask.cancel()
            return
        }

        // INJECT MISMATCHED SUB_ID FIRST
        // With old `return` behavior, this would terminate the stream
        await pool.injectTestEvent(subId: "wrong-sub-id", event: targetEvent, relay: testRelay)

        // INJECT CORRECT SUB_ID
        // With `continue` fix, this should still be received
        await pool.injectTestEvent(subId: actualSubId, event: targetEvent, relay: testRelay)

        await fulfillment(of: [eventReceived], timeout: 2.0)
        subscriptionTask.cancel()

        // KEY ASSERTION: Event was received despite mismatched event arriving first
        XCTAssertTrue(receivedEvents.contains(targetEvent.id),
            "Must receive event after mismatched sub_id - OLD `return` behavior would fail here")
    }

    /// Tests that two concurrent subscriptions each receive their own events
    /// when events are injected with interleaved sub_ids.
    ///
    /// This proves that one subscription receiving another's event doesn't
    /// terminate either subscription (the core bug scenario).
    func testInterleavedSubscriptionsReceiveCorrectEvents() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let testRelay = RelayURL("wss://test.relay.example")!

        // Create two distinct events
        let event1 = NostrEvent(
            content: "Event for subscription 1",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        let event2 = NostrEvent(
            content: "Event for subscription 2",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        let initialHandlerCount = await pool.testableHandlerSubIds.count
        var sub1Events: [NoteId] = []
        var sub2Events: [NoteId] = []
        let sub1Received = XCTestExpectation(description: "Sub 1 receives event 1")
        let sub2Received = XCTestExpectation(description: "Sub 2 receives event 2")

        // Start subscription 1
        let task1 = Task {
            let filter = NostrFilter(ids: [event1.id])
            for await item in await pool.subscribe(filters: [filter], eoseTimeout: .seconds(5)) {
                if case .event(let ev) = item {
                    sub1Events.append(ev.id)
                    if ev.id == event1.id { sub1Received.fulfill() }
                }
            }
        }

        // Wait for first handler
        try await waitForHandlers(pool: pool, count: initialHandlerCount + 1)

        // Start subscription 2
        let task2 = Task {
            let filter = NostrFilter(ids: [event2.id])
            for await item in await pool.subscribe(filters: [filter], eoseTimeout: .seconds(5)) {
                if case .event(let ev) = item {
                    sub2Events.append(ev.id)
                    if ev.id == event2.id { sub2Received.fulfill() }
                }
            }
        }

        // Wait for second handler
        try await waitForHandlers(pool: pool, count: initialHandlerCount + 2)

        // Get both sub_ids
        // Note: handlers are appended in order, so we can identify by position
        let subIds = await pool.testableHandlerSubIds
        guard subIds.count >= 2 else {
            XCTFail("Expected at least 2 handlers, got \(subIds.count)")
            task1.cancel()
            task2.cancel()
            return
        }

        let subId1 = subIds[subIds.count - 2]  // First subscription (second to last)
        let subId2 = subIds[subIds.count - 1]  // Second subscription (last)

        // INJECT INTERLEAVED: sub2's event, then sub1's event
        await pool.injectTestEvent(subId: subId2, event: event2, relay: testRelay)
        await pool.injectTestEvent(subId: subId1, event: event1, relay: testRelay)

        await fulfillment(of: [sub1Received, sub2Received], timeout: 2.0)
        task1.cancel()
        task2.cancel()

        // KEY ASSERTIONS: Each subscription got its correct event
        XCTAssertTrue(sub1Events.contains(event1.id), "Sub 1 must receive event 1")
        XCTAssertTrue(sub2Events.contains(event2.id), "Sub 2 must receive event 2")

        // Verify no cross-contamination
        XCTAssertFalse(sub1Events.contains(event2.id), "Sub 1 should NOT receive event 2")
        XCTAssertFalse(sub2Events.contains(event1.id), "Sub 2 should NOT receive event 1")
    }

}
