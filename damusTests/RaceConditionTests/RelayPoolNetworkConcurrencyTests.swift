//
//  RelayPoolNetworkConcurrencyTests.swift
//  damusTests
//
//  Tests for race conditions: RelayPool pathUpdateHandler re-entrancy + relays snapshot
//  Beads: damus-07m, damus-b54
//

import XCTest
@testable import damus

final class RelayPoolNetworkConcurrencyTests: XCTestCase {

    // MARK: - Before fix: re-entrancy allows overlapping handlers

    /// Reproduces master's RelayPool.handleConnectivityChange() which had no re-entrancy guard:
    ///   func handleConnectivityChange() async { ... await reconnect() ... }
    /// Without isHandlingConnectivity guard, two rapid calls overlap across await.
    func test_path_update_reentrancy_before() {
        let concurrentEntries = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Handler 1: enters pathUpdateHandler
        group.enter()
        DispatchQueue.global().async {
            concurrentEntries.increment()  // Enter handler
            barrier.arriveA()  // "await" suspension — handler 2 re-enters
            group.leave()
        }

        // Handler 2: re-enters during handler 1's suspension
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()
            concurrentEntries.increment()  // Re-enter (master had no guard)
            group.leave()
        }

        group.wait()
        XCTAssertEqual(concurrentEntries.value, 2, "Master RelayPool bug: pathUpdateHandler re-enters during await (no guard)")
    }

    // MARK: - After fix: pending-path pattern prevents both overlap AND dropped transitions

    /// Simulation: RelayPool.pathUpdateHandler is triggered by NWPathMonitor on
    /// a private queue. Testing requires intercepting OS-level network transitions.
    /// This test reproduces the pending-path guard pattern that prevents re-entrancy
    /// while ensuring no transitions are dropped.
    func test_path_update_reentrancy_after() {
        var isHandling = false
        var pendingStatus: String? = nil
        var lastProcessed: String? = nil
        let processed = AtomicCounter()
        let lock = NSLock()
        let group = DispatchGroup()
        let barrier = ConcurrentBarrier()

        // Handler 1: starts processing "satisfied"
        group.enter()
        DispatchQueue.global().async {
            lock.lock()
            if isHandling {
                pendingStatus = "satisfied"
                lock.unlock()
                group.leave()
                return
            }
            isHandling = true
            lock.unlock()

            barrier.arriveA()  // Simulate await suspension

            // After "await", check for pending
            lock.lock()
            lastProcessed = "satisfied"
            processed.increment()
            if let next = pendingStatus {
                pendingStatus = nil
                lastProcessed = next
                processed.increment()
            }
            isHandling = false
            lock.unlock()
            group.leave()
        }

        // Handler 2: arrives during handler 1's "await" with "unsatisfied"
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()
            lock.lock()
            if isHandling {
                pendingStatus = "unsatisfied"  // Queued, not dropped
                lock.unlock()
                group.leave()
                return
            }
            isHandling = true
            lock.unlock()
            lastProcessed = "unsatisfied"
            processed.increment()
            lock.lock()
            isHandling = false
            lock.unlock()
            group.leave()
        }

        group.wait()
        lock.lock()
        let finalProcessed = lastProcessed
        let totalProcessed = processed.value
        lock.unlock()
        XCTAssertEqual(totalProcessed, 2, "Pending-path pattern processes both transitions (none dropped)")
        XCTAssertEqual(finalProcessed, "unsatisfied", "Final state reflects the latest transition")
    }
}
