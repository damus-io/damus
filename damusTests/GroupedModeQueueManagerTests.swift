//
//  GroupedModeQueueManagerTests.swift
//  damusTests
//
//  Created by alltheseas on 2025-12-07.
//

import XCTest
@testable import damus

@MainActor
final class GroupedModeQueueManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makeEvent(
        content: String = "Test event with enough content to avoid filtering",
        keypair: Keypair = test_keypair,
        secondsAgo: UInt32 = 100
    ) -> NostrEvent {
        NostrEvent(
            content: content,
            keypair: keypair,
            createdAt: UInt32(Date().timeIntervalSince1970) - secondsAgo
        )!
    }

    // MARK: - Flush Moves Queued Events

    func testFlushMovesQueuedEventsToMainList() {
        let holder = EventHolder()
        holder.set_should_queue(true)

        let event = makeEvent()
        let _ = holder.insert(event)

        XCTAssertEqual(holder.events.count, 0, "Event should be queued, not in main list")
        XCTAssertEqual(holder.incoming.count, 1, "Event should be in incoming queue")

        GroupedModeQueueManager.flush(source: holder)

        XCTAssertEqual(holder.events.count, 1, "Event should be in main list after flush")
        XCTAssertEqual(holder.incoming.count, 0, "Incoming queue should be empty after flush")
    }

    // MARK: - Flush Disables Queueing

    func testFlushDisablesQueueing() {
        let holder = EventHolder()
        holder.set_should_queue(true)

        XCTAssertTrue(holder.should_queue, "Queueing should be enabled before flush")

        GroupedModeQueueManager.flush(source: holder)

        XCTAssertFalse(holder.should_queue, "Queueing should be disabled after flush")
    }

    // MARK: - Flush Is Idempotent

    func testFlushIsIdempotent() {
        let holder = EventHolder()
        holder.set_should_queue(true)

        let event = makeEvent()
        let _ = holder.insert(event)

        GroupedModeQueueManager.flush(source: holder)
        let countAfterFirst = holder.events.count

        // Second flush with no new events
        GroupedModeQueueManager.flush(source: holder)
        let countAfterSecond = holder.events.count

        XCTAssertEqual(countAfterFirst, countAfterSecond, "Second flush should not change event count")
        XCTAssertEqual(holder.events.count, 1, "Should still have exactly 1 event")
    }
}
