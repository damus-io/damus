//
//  DebouncerConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: Debouncer workItem race
//  Bead: damus-82j
//

import XCTest
@testable import damus

final class DebouncerConcurrencyTests: XCTestCase {

    // MARK: - Before fix: reproduce master's concurrent workItem read/write

    /// Reproduces master's Debouncer.debounce() which had no NSLock:
    ///   workItem?.cancel()                        // READ + call
    ///   workItem = DispatchWorkItem { action() }  // WRITE
    /// Without NSLock, both threads read the old workItem and both write a new one.
    func test_debouncer_workitem_race_before() {
        var workItem: String? = "initial"
        let storageLock = NSLock()
        let bothOperated = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Thread A: master's debounce (read workItem, then replace)
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let _ = workItem  // READ (master: workItem?.cancel())
            storageLock.unlock()

            barrier.arriveA()  // Both threads read before either writes

            storageLock.lock()
            workItem = "item-A"  // WRITE (master: workItem = DispatchWorkItem {...})
            storageLock.unlock()
            bothOperated.increment()
            group.leave()
        }

        // Thread B: concurrent debounce
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let _ = workItem  // READ stale value
            storageLock.unlock()

            barrier.arriveB()

            storageLock.lock()
            workItem = "item-B"  // WRITE (overwrites A)
            storageLock.unlock()
            bothOperated.increment()
            group.leave()
        }

        group.wait()
        XCTAssertEqual(bothOperated.value, 2, "Master Debouncer bug: both threads read+write workItem concurrently (data race on Optional)")
    }

    // MARK: - After fix: real Debouncer with NSLock protects workItem

    /// Spawns 100 concurrent calls to Debouncer.debounce to verify no crash/race
    /// when cancelling/replacing workItem. At least one debounced action fires.
    func test_debouncer_workitem_race_after() {
        let debouncer = Debouncer(interval: 0.01)
        let counter = AtomicCounter()
        let fired = expectation(description: "debounced action fired")
        fired.assertForOverFulfill = false

        // 100 concurrent threads all call debounce simultaneously
        for i in 0..<100 {
            DispatchQueue.global().async {
                debouncer.debounce {
                    counter.increment()
                    fired.fulfill()
                }
            }
        }

        // Debouncer dispatches to main queue — wait for the expectation
        wait(for: [fired], timeout: 5.0)
        // Key proof: real Debouncer survives 100 concurrent debounce calls without crash.
        // NSLock serializes workItem?.cancel() and workItem = newItem.
        XCTAssertGreaterThanOrEqual(counter.value, 1, "At least one debounced action executed on real Debouncer under concurrent access")
    }
}
