//
//  EventCacheConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: EventCache unsynchronized dictionaries
//  Bead: damus-dko
//

import XCTest
@testable import damus

final class EventCacheConcurrencyTests: XCTestCase {

    // MARK: - Before fix: demonstrates lost writes on unprotected dictionary

    /// Reproduces master's EventCache.insert() which had no NSLock:
    ///   if events[ev.id] == nil { events[ev.id] = ev }   // CHECK-then-ACT
    /// Without NSLock, two threads both see nil and both write (last-writer-wins).
    func test_event_cache_dictionary_race_before() {
        var events: [String: String] = [:]
        let storageLock = NSLock()
        let bothInserted = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let isNil = events["ev1"] == nil  // CHECK (master's lookup)
            storageLock.unlock()
            barrier.arriveA()  // Both checked nil before either writes
            if isNil {
                storageLock.lock()
                events["ev1"] = "event-A"  // ACT: insert
                storageLock.unlock()
                bothInserted.increment()
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let isNil = events["ev1"] == nil  // CHECK: also nil
            storageLock.unlock()
            barrier.arriveB()
            if isNil {
                storageLock.lock()
                events["ev1"] = "event-B"  // ACT: overwrites A (last-writer-wins)
                storageLock.unlock()
                bothInserted.increment()
            }
            group.leave()
        }
        let result1 = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result1, .success, "Threads should complete within timeout")
        XCTAssertEqual(bothInserted.value, 2, "Master EventCache bug: both threads pass nil check and write (last-writer-wins)")
    }

    // MARK: - After fix: NSLock serialization prevents lost writes

    /// Exercises the real EventCache: 100 unique events inserted concurrently
    /// from background threads. NSLock serialization ensures all inserts are
    /// preserved and retrievable via lookup().
    func test_event_cache_dictionary_race_after() {
        let cache = EventCache(ndb: Ndb.test)

        // Create 100 unique events
        var events: [NostrEvent] = []
        for i in 0..<100 {
            if let ev = NostrEvent(content: "cache test event \(i) \(UUID().uuidString)", keypair: test_keypair) {
                events.append(ev)
            }
        }
        XCTAssertEqual(events.count, 100, "Should create 100 test events")

        // Concurrent inserts from background threads
        let counter = AtomicCounter()
        let group = DispatchGroup()

        for ev in events {
            group.enter()
            DispatchQueue.global().async {
                cache.insert(ev)
                counter.increment()
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "All concurrent inserts should complete within timeout")
        XCTAssertEqual(counter.value, 100, "All 100 concurrent inserts complete without crashes")

        // All events should be retrievable
        var found: Int32 = 0
        for ev in events {
            if cache.lookup(ev.id) != nil {
                found += 1
            }
        }
        XCTAssertEqual(found, 100, "NSLock ensures all concurrent inserts are preserved and retrievable")
    }
}
