//
//  EventHolderConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: EventHolder non-MainActor mutations of @Published events
//

import XCTest
@testable import damus

final class EventHolderConcurrencyTests: XCTestCase {
    /// Exercises the real EventHolder class: 100 concurrent tasks try to insert
    /// the same event. @MainActor serialization ensures only one insert succeeds
    /// (has_event check-then-insert is atomic).
    func test_event_holder_filter_race_after() async {
        let holder = await MainActor.run { EventHolder() }

        guard let testEvent = NostrEvent(content: "dedup test event", keypair: test_keypair) else {
            XCTFail("Could not create test event")
            return
        }

        // 100 concurrent tasks all try to insert the same event
        let successCount = await concurrentStressAsync(workers: 10, iterations: 10) { _, _ in
            await holder.insert(testEvent)
        }

        // @MainActor serializes insert: only first insert succeeds
        XCTAssertEqual(successCount, 1, "@MainActor serialization ensures only one insert of same event succeeds")

        let eventsCount = await MainActor.run { holder.events.count }
        XCTAssertEqual(eventsCount, 1, "Only one copy of the event in the events array")
    }
}
