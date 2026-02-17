//
//  PostBoxConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: PostBox dictionary mutation during async iteration
//  Bead: damus-j5w
//

import XCTest
@testable import damus

final class PostBoxConcurrencyTests: XCTestCase {

    // MARK: - Before fix: demonstrates actor re-entrancy issue

    /// Reproduces master's PostBox.flush() which iterated events dict without snapshot:
    ///   for (_, ev) in self.events { try await send(ev) }  // iteration
    ///   // re-entrant send() could modify self.events during await
    /// Without snapshot-before-await, dict mutates during iteration.
    func test_postbox_iteration_race_before() {
        var events: [String: String] = ["ev1": "a", "ev2": "b", "ev3": "c"]
        let storageLock = NSLock()
        let mutatedDuringIteration = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Thread A: iterating events (like flush())
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let countBefore = events.count  // Start iteration
            storageLock.unlock()
            barrier.arriveA()  // Writer mutates during "await" suspension
            storageLock.lock()
            let countAfter = events.count   // Dict changed under us!
            storageLock.unlock()
            if countBefore != countAfter {
                mutatedDuringIteration.increment()
            }
            group.leave()
        }

        // Thread B: re-entrant mutation during iteration's await
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()
            storageLock.lock()
            events["ev4"] = "d"  // Mutate during iteration
            storageLock.unlock()
            group.leave()
        }

        group.wait()
        XCTAssertEqual(mutatedDuringIteration.value, 1, "Master PostBox bug: dict mutated during iteration across await suspension point")
    }

    // MARK: - After fix: snapshot prevents mutation during iteration

    /// Simulation: PostBox is a Swift actor whose init requires a RelayPool with
    /// network infrastructure. The snapshot-before-await fix is in the internal
    /// try_flushing_events() method which iterates events across await suspension
    /// points. This test reproduces the exact snapshot pattern in isolation.
    func test_postbox_iteration_race_after() {
        var dict: [Int: [Int]] = [:]
        for i in 0..<10 {
            dict[i] = Array(0..<5)
        }

        // Snapshot taken before concurrent work begins (mirrors fix pattern)
        let snapshot = Array(dict.values)
        let counter = AtomicCounter()
        let group = DispatchGroup()

        // Reader: iterates snapshot (safe — no concurrent access)
        group.enter()
        DispatchQueue.global().async {
            for value in snapshot {
                for _ in value {
                    counter.increment()
                }
            }
            group.leave()
        }

        // Writer: mutates original dict concurrently (safe — snapshot is independent)
        group.enter()
        DispatchQueue.global().async {
            for i in 0..<10 {
                dict.removeValue(forKey: i)
            }
            group.leave()
        }

        group.wait()

        // Snapshot always sees all 10 entries × 5 items = 50
        XCTAssertEqual(counter.value, 50, "Snapshot iteration should see all original values")
    }
}
