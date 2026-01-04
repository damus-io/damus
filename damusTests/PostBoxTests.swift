//
//  PostBoxTests.swift
//  damusTests
//
//  Tests for PostBox event publishing under various network conditions.
//

import Foundation
import XCTest
@testable import damus

/// Tests for PostBox event queuing, sending, and OK response handling.
final class PostBoxTests: XCTestCase {

    var pool: RelayPool!
    var postbox: PostBox!
    var mockSocket: MockWebSocket!
    var ndb: Ndb!

    let testRelayURL = RelayURL("wss://test.relay.com")!

    override func setUp() async throws {
        try await super.setUp()
        ndb = Ndb.test
        pool = RelayPool(ndb: ndb)

        // Add relay with mock socket
        mockSocket = MockWebSocket()
        let descriptor = RelayPool.RelayDescriptor(url: testRelayURL, info: .readWrite)
        try await pool.add_relay(descriptor, webSocket: mockSocket)

        postbox = PostBox(pool: pool)

        // Connect the relay
        await pool.connect()
        mockSocket.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await pool.close()
        pool = nil
        postbox = nil
        mockSocket = nil
        ndb = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    /// Creates a test NostrEvent with the given content
    func makeTestEvent(content: String = "Test post") -> NostrEvent? {
        // Create a minimal test event
        let keypair = test_keypair_full
        let post = NostrPost(content: content, kind: .text, tags: [])
        return post.to_event(keypair: keypair)
    }

    /// Simulates an OK response from the relay
    func simulateOKResponse(eventId: NoteId, success: Bool = true, message: String = "") {
        let result = CommandResult(event_id: eventId, ok: success, msg: message)
        let response = NostrResponse.ok(result)
        postbox.handle_event(relay_id: testRelayURL, .nostr_event(response))
    }

    // MARK: - Basic Send Tests

    /// Test: Event is added to queue when sent
    func testEventAddedToQueue() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL])

        XCTAssertNotNil(postbox.events[event.id], "Event should be in queue after send")
        XCTAssertEqual(postbox.events.count, 1, "Should have exactly 1 event in queue")
    }

    /// Test: Duplicate events are not added to queue
    func testDuplicateEventNotAdded() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL])
        await postbox.send(event, to: [testRelayURL]) // Send again

        XCTAssertEqual(postbox.events.count, 1, "Should still have only 1 event")
    }

    /// Test: Event is sent to relay (WebSocket receives message)
    func testEventSentToRelay() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        // Check that something was sent to the mock socket
        XCTAssertGreaterThan(mockSocket.sentMessages.count, 0, "Should have sent message to relay")

        // Verify the message contains EVENT
        if let sentMessage = mockSocket.sentMessages.first {
            if case .string(let str) = sentMessage {
                XCTAssertTrue(str.contains("EVENT"), "Message should be an EVENT")
            } else {
                XCTFail("Expected string message")
            }
        }
    }

    // MARK: - OK Response Handling

    /// Test: Event removed from queue on successful OK response
    func testEventRemovedOnOK() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL])
        XCTAssertNotNil(postbox.events[event.id])

        // Simulate OK response
        simulateOKResponse(eventId: event.id, success: true)

        XCTAssertNil(postbox.events[event.id], "Event should be removed after OK")
        XCTAssertEqual(postbox.events.count, 0, "Queue should be empty")
    }

    /// Test: Event removed even on failed OK response (relay rejected)
    func testEventRemovedOnFailedOK() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL])

        // Simulate failed OK (relay rejected the event)
        simulateOKResponse(eventId: event.id, success: false, message: "blocked: you are banned")

        XCTAssertNil(postbox.events[event.id], "Event should be removed even on failure")
    }

    /// Test: OK with "duplicate:" prefix still removes event
    func testDuplicateOKRemovesEvent() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL])

        simulateOKResponse(eventId: event.id, success: true, message: "duplicate: already have this event")

        XCTAssertNil(postbox.events[event.id], "Event should be removed on duplicate OK")
    }

    // MARK: - Multi-Relay Tests

    /// Test: Event tracks multiple relays in remaining list
    func testMultiRelayRemaining() async throws {
        let relay2URL = RelayURL("wss://relay2.test.com")!
        let mockSocket2 = MockWebSocket()
        let descriptor2 = RelayPool.RelayDescriptor(url: relay2URL, info: .readWrite)
        try await pool.add_relay(descriptor2, webSocket: mockSocket2)
        mockSocket2.simulateConnect()

        try await Task.sleep(for: .milliseconds(100))

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL, relay2URL])

        let postedEvent = postbox.events[event.id]
        XCTAssertNotNil(postedEvent)
        XCTAssertEqual(postedEvent?.remaining.count, 2, "Should have 2 relays in remaining")
    }

    /// Test: Event not removed until all relays respond
    func testEventRemainsUntilAllRelaysRespond() async throws {
        let relay2URL = RelayURL("wss://relay2.test.com")!
        let mockSocket2 = MockWebSocket()
        let descriptor2 = RelayPool.RelayDescriptor(url: relay2URL, info: .readWrite)
        try await pool.add_relay(descriptor2, webSocket: mockSocket2)
        mockSocket2.simulateConnect()

        try await Task.sleep(for: .milliseconds(100))

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL, relay2URL])

        // First relay responds
        simulateOKResponse(eventId: event.id)

        // Event should still exist (waiting for relay2)
        XCTAssertNotNil(postbox.events[event.id], "Event should remain until all relays respond")
        XCTAssertEqual(postbox.events[event.id]?.remaining.count, 1, "Should have 1 relay remaining")

        // Second relay responds
        let result2 = CommandResult(event_id: event.id, ok: true, msg: "")
        postbox.handle_event(relay_id: relay2URL, .nostr_event(.ok(result2)))

        // Now event should be removed
        XCTAssertNil(postbox.events[event.id], "Event should be removed after all relays respond")
    }

    // MARK: - OnFlush Callback Tests

    /// Test: on_flush .once callback fires on first OK
    func testOnFlushOnceCallback() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        var callbackCount = 0
        let expectation = XCTestExpectation(description: "Callback should fire")

        await postbox.send(event, to: [testRelayURL], on_flush: .once({ _ in
            callbackCount += 1
            expectation.fulfill()
        }))

        simulateOKResponse(eventId: event.id)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(callbackCount, 1, "Callback should fire exactly once")
    }

    /// Test: on_flush .once callback fires only once even with multiple relays
    func testOnFlushOnceFiresOnlyOnce() async throws {
        let relay2URL = RelayURL("wss://relay2.test.com")!
        let mockSocket2 = MockWebSocket()
        let descriptor2 = RelayPool.RelayDescriptor(url: relay2URL, info: .readWrite)
        try await pool.add_relay(descriptor2, webSocket: mockSocket2)
        mockSocket2.simulateConnect()

        try await Task.sleep(for: .milliseconds(100))

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        var callbackCount = 0

        await postbox.send(event, to: [testRelayURL, relay2URL], on_flush: .once({ _ in
            callbackCount += 1
        }))

        // Both relays respond
        simulateOKResponse(eventId: event.id)
        let result2 = CommandResult(event_id: event.id, ok: true, msg: "")
        postbox.handle_event(relay_id: relay2URL, .nostr_event(.ok(result2)))

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(callbackCount, 1, ".once callback should fire only once")
    }

    /// Test: on_flush .all callback fires for each relay
    func testOnFlushAllCallback() async throws {
        let relay2URL = RelayURL("wss://relay2.test.com")!
        let mockSocket2 = MockWebSocket()
        let descriptor2 = RelayPool.RelayDescriptor(url: relay2URL, info: .readWrite)
        try await pool.add_relay(descriptor2, webSocket: mockSocket2)
        mockSocket2.simulateConnect()

        try await Task.sleep(for: .milliseconds(100))

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        var callbackCount = 0

        await postbox.send(event, to: [testRelayURL, relay2URL], on_flush: .all({ _ in
            callbackCount += 1
        }))

        // Both relays respond
        simulateOKResponse(eventId: event.id)
        let result2 = CommandResult(event_id: event.id, ok: true, msg: "")
        postbox.handle_event(relay_id: relay2URL, .nostr_event(.ok(result2)))

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(callbackCount, 2, ".all callback should fire for each relay")
    }

    // MARK: - Delayed Send Tests

    /// Test: Delayed event not flushed immediately
    func testDelayedEventNotFlushedImmediately() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        mockSocket.reset()

        // Send with 5 second delay
        await postbox.send(event, to: [testRelayURL], delay: 5.0)

        // Event should be in queue
        XCTAssertNotNil(postbox.events[event.id])

        // But nothing should have been sent yet
        XCTAssertEqual(mockSocket.sentMessages.count, 0, "Delayed event should not be sent immediately")
    }

    /// Test: Cancel delayed send before flush
    func testCancelDelayedSend() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL], delay: 5.0)
        XCTAssertNotNil(postbox.events[event.id])

        let cancelResult = postbox.cancel_send(evid: event.id)

        XCTAssertNil(cancelResult, "Cancel should succeed (return nil)")
        XCTAssertNil(postbox.events[event.id], "Event should be removed after cancel")
    }

    /// Test: Cannot cancel non-delayed event
    func testCannotCancelNonDelayedEvent() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL]) // No delay

        let cancelResult = postbox.cancel_send(evid: event.id)

        XCTAssertEqual(cancelResult, .not_delayed, "Should return not_delayed error")
    }

    /// Test: Cannot cancel non-existent event
    func testCannotCancelNonExistentEvent() async throws {
        let fakeId = NoteId(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!

        let cancelResult = postbox.cancel_send(evid: fakeId)

        XCTAssertEqual(cancelResult, .nothing_to_cancel, "Should return nothing_to_cancel error")
    }

    // MARK: - Retry Logic Tests

    /// Test: Relayer tracks attempt count
    func testRelayerTracksAttempts() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL])

        let postedEvent = postbox.events[event.id]
        XCTAssertNotNil(postedEvent)

        // First attempt should have been made
        let relayer = postedEvent?.remaining.first
        XCTAssertNotNil(relayer)
        XCTAssertEqual(relayer?.attempts, 1, "Should have 1 attempt after send")
        XCTAssertNotNil(relayer?.last_attempt, "Should have recorded last_attempt time")
    }

    /// Test: Retry increases backoff time
    func testRetryIncreasesBackoff() async throws {
        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        await postbox.send(event, to: [testRelayURL])

        let postedEvent = postbox.events[event.id]
        let relayer = postedEvent?.remaining.first

        // Initial backoff is 10s, after first attempt it should be 10 * 1.5 = 15
        XCTAssertEqual(relayer?.retry_after, 15.0, "Backoff should increase by 1.5x after attempt")
    }
}
