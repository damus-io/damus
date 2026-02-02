//
//  EventHolderTests.swift
//  damusTests
//
//  Tests for EventHolder queue behavior under various conditions.
//

import Foundation
import XCTest
@testable import damus

/// Tests for EventHolder event queuing, deduplication, and flushing.
@MainActor
final class EventHolderTests: XCTestCase {

    // MARK: - Helper Methods

    /// Creates a test NostrEvent with the given content
    func makeTestEvent(content: String = "Test", createdAt: UInt32? = nil) -> NostrEvent? {
        let keypair = test_keypair_full
        let tags: [[String]] = []
        let created = createdAt ?? UInt32(Date().timeIntervalSince1970)
        return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: 1, tags: tags, createdAt: created)
    }

    // MARK: - Basic Queue Tests

    /// Test: Events go to immediate display when should_queue is false
    func testImmediateInsertWhenNotQueuing() async throws {
        let holder = EventHolder()
        holder.set_should_queue(false)

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        let inserted = holder.insert(event)

        XCTAssertTrue(inserted, "Event should be inserted")
        XCTAssertEqual(holder.events.count, 1, "Event should be in events array")
        XCTAssertEqual(holder.incoming.count, 0, "Incoming queue should be empty")
    }

    /// Test: Events go to incoming queue when should_queue is true
    func testQueuedInsertWhenQueuing() async throws {
        let holder = EventHolder()
        holder.set_should_queue(true)

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        let inserted = holder.insert(event)

        XCTAssertTrue(inserted, "Event should be inserted")
        XCTAssertEqual(holder.events.count, 0, "Events array should be empty")
        XCTAssertEqual(holder.incoming.count, 1, "Event should be in incoming queue")
    }

    /// Test: Queued events are flushed to events array
    func testFlushMovesQueuedEvents() async throws {
        let holder = EventHolder()
        holder.set_should_queue(true)

        guard let event1 = makeTestEvent(content: "Event 1"),
              let event2 = makeTestEvent(content: "Event 2") else {
            XCTFail("Failed to create test events")
            return
        }

        holder.insert(event1)
        holder.insert(event2)

        XCTAssertEqual(holder.incoming.count, 2)
        XCTAssertEqual(holder.events.count, 0)

        holder.flush()

        XCTAssertEqual(holder.incoming.count, 0, "Incoming should be empty after flush")
        XCTAssertEqual(holder.events.count, 2, "Events should contain flushed events")
    }

    // MARK: - Deduplication Tests

    /// Test: Duplicate events are rejected in immediate mode
    func testDeduplicationImmediate() async throws {
        let holder = EventHolder()
        holder.set_should_queue(false)

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        let first = holder.insert(event)
        let second = holder.insert(event) // Same event again

        XCTAssertTrue(first, "First insert should succeed")
        XCTAssertFalse(second, "Second insert should be rejected")
        XCTAssertEqual(holder.events.count, 1, "Should only have 1 event")
    }

    /// Test: Duplicate events are rejected in queue mode
    func testDeduplicationQueued() async throws {
        let holder = EventHolder()
        holder.set_should_queue(true)

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        let first = holder.insert(event)
        let second = holder.insert(event)

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(holder.incoming.count, 1)
    }

    /// Test: Event queued then inserted immediately is deduplicated
    func testDeduplicationAcrossQueueAndImmediate() async throws {
        let holder = EventHolder()

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        // First insert while queuing
        holder.set_should_queue(true)
        let first = holder.insert(event)

        // Switch to immediate and try again
        holder.set_should_queue(false)
        let second = holder.insert(event)

        XCTAssertTrue(first)
        XCTAssertFalse(second, "Should reject duplicate even when switching modes")
    }

    // MARK: - Ordering Tests

    /// Test: Events are sorted by created_at (newest first)
    func testEventsSortedByCreatedAt() async throws {
        let holder = EventHolder()
        holder.set_should_queue(false)

        let now = UInt32(Date().timeIntervalSince1970)

        guard let oldEvent = makeTestEvent(content: "Old", createdAt: now - 100),
              let newEvent = makeTestEvent(content: "New", createdAt: now) else {
            XCTFail("Failed to create test events")
            return
        }

        // Insert in reverse order
        holder.insert(oldEvent)
        holder.insert(newEvent)

        XCTAssertEqual(holder.events.count, 2)
        XCTAssertEqual(holder.events.first?.content, "New", "Newest event should be first")
        XCTAssertEqual(holder.events.last?.content, "Old", "Oldest event should be last")
    }

    // MARK: - Queue Callback Tests

    /// Test: on_queue callback fires when event is queued
    func testOnQueueCallbackFires() async throws {
        var callbackCount = 0
        let holder = EventHolder(on_queue: { _ in
            callbackCount += 1
        })
        holder.set_should_queue(true)

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        holder.insert(event)

        XCTAssertEqual(callbackCount, 1, "on_queue callback should fire once")
    }

    /// Test: on_queue callback does not fire in immediate mode
    func testOnQueueCallbackNotFiredImmediate() async throws {
        var callbackCount = 0
        let holder = EventHolder(on_queue: { _ in
            callbackCount += 1
        })
        holder.set_should_queue(false)

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        holder.insert(event)

        XCTAssertEqual(callbackCount, 0, "on_queue should not fire in immediate mode")
    }

    // MARK: - All Events Tests

    /// Test: all_events returns both visible and queued events
    func testAllEventsIncludesBoth() async throws {
        let holder = EventHolder()

        guard let immediateEvent = makeTestEvent(content: "Immediate"),
              let queuedEvent = makeTestEvent(content: "Queued") else {
            XCTFail("Failed to create test events")
            return
        }

        // Add immediate event
        holder.set_should_queue(false)
        holder.insert(immediateEvent)

        // Add queued event
        holder.set_should_queue(true)
        holder.insert(queuedEvent)

        XCTAssertEqual(holder.events.count, 1)
        XCTAssertEqual(holder.incoming.count, 1)
        XCTAssertEqual(holder.all_events.count, 2, "all_events should include both")
    }

    // MARK: - Reset Tests

    /// Test: Reset clears all events
    func testResetClearsAll() async throws {
        let holder = EventHolder()

        guard let event1 = makeTestEvent(content: "1"),
              let event2 = makeTestEvent(content: "2") else {
            XCTFail("Failed to create test events")
            return
        }

        holder.set_should_queue(false)
        holder.insert(event1)

        holder.set_should_queue(true)
        holder.insert(event2)

        XCTAssertEqual(holder.events.count, 1)
        XCTAssertEqual(holder.incoming.count, 1)

        holder.reset()

        XCTAssertEqual(holder.events.count, 0, "Events should be cleared")
        XCTAssertEqual(holder.incoming.count, 0, "Incoming should be cleared")
    }

    // MARK: - Empty Flush Tests

    /// Test: Flush on empty queue does nothing
    func testFlushEmptyQueueNoOp() async throws {
        let holder = EventHolder()

        guard let event = makeTestEvent() else {
            XCTFail("Failed to create test event")
            return
        }

        holder.set_should_queue(false)
        holder.insert(event)

        let countBefore = holder.events.count

        holder.flush() // Should be no-op

        XCTAssertEqual(holder.events.count, countBefore, "Flush should not affect events")
    }

    // MARK: - Queued Count Tests

    /// Test: queued property returns correct count
    func testQueuedCountAccurate() async throws {
        let holder = EventHolder()
        holder.set_should_queue(true)

        XCTAssertEqual(holder.queued, 0)

        guard let event1 = makeTestEvent(content: "1"),
              let event2 = makeTestEvent(content: "2"),
              let event3 = makeTestEvent(content: "3") else {
            XCTFail("Failed to create test events")
            return
        }

        holder.insert(event1)
        XCTAssertEqual(holder.queued, 1)

        holder.insert(event2)
        holder.insert(event3)
        XCTAssertEqual(holder.queued, 3)

        holder.flush()
        XCTAssertEqual(holder.queued, 0)
    }
}
