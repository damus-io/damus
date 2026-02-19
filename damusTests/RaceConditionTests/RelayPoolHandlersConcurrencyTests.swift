//
//  RelayPoolHandlersConcurrencyTests.swift
//  damusTests
//
//  Tests for race conditions: RelayPool handler array iteration + seen/counts
//  Beads: damus-4np, damus-je2
//

import XCTest
@testable import damus

final class RelayPoolHandlersConcurrencyTests: XCTestCase {

    // MARK: - Before fix: array mutation during iteration

    /// Reproduces master's RelayPool handler iteration without snapshot:
    ///   for handler in handlers { handler.notify(.event(...)) }  // iteration
    ///   // concurrent add_handler() mutates handlers array
    /// Without snapshot, array mutates during iteration.
    func test_handler_array_race_before() {
        var handlers: [String] = ["h1", "h2", "h3"]
        let storageLock = NSLock()
        let mutatedDuringIteration = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Thread A: iterating handlers
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let countBefore = handlers.count  // Start iteration
            storageLock.unlock()
            barrier.arriveA()  // Writer appends during iteration
            storageLock.lock()
            let countAfter = handlers.count
            storageLock.unlock()
            if countBefore != countAfter {
                mutatedDuringIteration.increment()
            }
            group.leave()
        }

        // Thread B: appends during iteration
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()
            storageLock.lock()
            handlers.append("h4")
            storageLock.unlock()
            group.leave()
        }

        let result1 = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result1, .success, "Threads should complete within timeout")
        XCTAssertEqual(mutatedDuringIteration.value, 1, "Master RelayPool bug: handler array mutated during iteration (can crash or skip elements)")
    }

    // MARK: - After fix: snapshot before iteration

    /// Simulation: RelayPool's handler iteration fix is in internal handle_event()
    /// and resubscribeAll() methods behind @RelayPoolActor isolation. Testing
    /// requires active relay connections. This test reproduces the snapshot pattern.
    func test_handler_array_race_after() {
        let handlers: [String] = Array(0..<100).map { "handler-\($0)" }
        // Snapshot taken before concurrent work (mirrors fix pattern)
        let snapshot = handlers
        var mutableHandlers = handlers
        let counter = AtomicCounter()
        let group = DispatchGroup()

        // Reader: iterates snapshot (safe)
        group.enter()
        DispatchQueue.global().async {
            for _ in snapshot {
                counter.increment()
            }
            group.leave()
        }

        // Writer: mutates mutable copy concurrently (safe — snapshot is independent)
        group.enter()
        DispatchQueue.global().async {
            mutableHandlers.append("new-handler")
            mutableHandlers.removeFirst()
            group.leave()
        }

        let result2 = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result2, .success, "Threads should complete within timeout")
        XCTAssertEqual(counter.value, 100, "Snapshot should see exactly 100 original handlers")
    }

    // MARK: - seen/counts dictionary race

    /// Reproduces master's RelayPool counts dict without actor isolation:
    ///   counts[relay, default: 0] += 1  // READ-MODIFY-WRITE (non-atomic)
    /// Without isolation, two threads both read 0, both write 1 → lost update.
    func test_seen_counts_race_before() {
        var counts: [String: Int] = [:]
        let storageLock = NSLock()
        let bothIncremented = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let current = counts["relay1", default: 0]  // READ: 0
            storageLock.unlock()
            barrier.arriveA()  // Both read 0 before either writes
            storageLock.lock()
            counts["relay1"] = current + 1  // WRITE: sets to 1
            storageLock.unlock()
            bothIncremented.increment()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let current = counts["relay1", default: 0]  // READ: also 0
            storageLock.unlock()
            barrier.arriveB()
            storageLock.lock()
            counts["relay1"] = current + 1  // WRITE: also sets to 1 (lost update!)
            storageLock.unlock()
            bothIncremented.increment()
            group.leave()
        }

        let result3 = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result3, .success, "Threads should complete within timeout")
        storageLock.lock()
        let finalCount = counts["relay1"] ?? 0
        storageLock.unlock()
        XCTAssertEqual(bothIncremented.value, 2, "Master RelayPool bug: both threads increment concurrently")
        XCTAssertEqual(finalCount, 1, "Lost update: should be 2 but got 1 (both read 0 then wrote 1)")
    }

    /// Simulation: RelayPool counts are protected by @RelayPoolActor isolation.
    /// Testing requires active relay connections. Serial queue here mirrors
    /// the actor's serialization guarantee.
    func test_seen_counts_race_after() {
        // With RelayPoolActor isolation (as in production), all access is serialized
        // Simulate with a serial queue
        var counts: [String: Int] = [:]
        let queue = DispatchQueue(label: "serial")
        let group = DispatchGroup()

        for _ in 0..<10 {
            group.enter()
            queue.async {
                for _ in 0..<100 {
                    counts["relay1", default: 0] += 1
                }
                group.leave()
            }
        }

        let result4 = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result4, .success, "All serialized increments should complete within timeout")
        XCTAssertEqual(counts["relay1"], 1000, "Serialized access preserves all 1000 increments")
    }
}
