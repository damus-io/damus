//
//  EventHolderConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: EventHolder non-MainActor mutations of @Published events
//  Bead: damus-o5x
//

import XCTest
@testable import damus

final class EventHolderConcurrencyTests: XCTestCase {

    // MARK: - Before fix: concurrent filter + insert causes inconsistency

    /// Reproduces master's EventHolder.filter() which had no @MainActor:
    ///   events = events.filter { ... }   // mutates events array
    ///   // but has_event Set not updated atomically with events
    /// Without @MainActor, another thread sees has_event and events out of sync.
    func test_event_holder_filter_race_before() {
        var hasEvent = Set<String>(["ev1", "ev2", "ev3"])
        var events: [String] = ["ev1", "ev2", "ev3"]
        let storageLock = NSLock()
        let outOfSync = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Second sync: ensures Thread B reads AFTER Thread A filters but BEFORE Thread A updates hasEvent
        let bDone = DispatchSemaphore(value: 0)

        // Thread A: filter (removes ev2 from events but not hasEvent yet)
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            events = events.filter { $0 != "ev2" }  // Remove from events
            storageLock.unlock()
            barrier.arriveA()  // Signal: events filtered
            bDone.wait()       // Wait for Thread B to observe the desync
            storageLock.lock()
            hasEvent.remove("ev2")  // Eventually update hasEvent
            storageLock.unlock()
            group.leave()
        }

        // Thread B: read during desync window
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()  // Wait for Thread A to filter events
            storageLock.lock()
            let inHasEvent = hasEvent.contains("ev2")  // Still true!
            let inEvents = events.contains("ev2")       // But gone from events!
            storageLock.unlock()
            bDone.signal()     // Let Thread A proceed to update hasEvent
            if inHasEvent && !inEvents {
                outOfSync.increment()
            }
            group.leave()
        }

        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "Threads should complete within timeout")
        XCTAssertEqual(outOfSync.value, 1, "Master EventHolder bug: has_event and events desync when filter runs without @MainActor")
    }

    // MARK: - After fix: @MainActor serializes filter and insert

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
            await MainActor.run {
                return holder.insert(testEvent)
            }
        }

        // @MainActor serializes insert: only first insert succeeds
        XCTAssertEqual(successCount, 1, "@MainActor serialization ensures only one insert of same event succeeds")

        let eventsCount = await MainActor.run { holder.events.count }
        XCTAssertEqual(eventsCount, 1, "Only one copy of the event in the events array")
    }
}
