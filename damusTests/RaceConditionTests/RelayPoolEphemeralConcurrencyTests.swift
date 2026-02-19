//
//  RelayPoolEphemeralConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: RelayPool ephemeral lease TOCTOU
//  Bead: damus-00r
//

import XCTest
@testable import damus

final class RelayPoolEphemeralConcurrencyTests: XCTestCase {

    // MARK: - Before fix: lease count can change across await

    /// Reproduces master's RelayPool ephemeral lease release without re-check:
    ///   ephemeralLeases[url] = nil            // release
    ///   guard ephemeralLeases[url] == nil ...  // CHECK (true)
    ///   await Task.sleep(...)                  // SUSPENSION
    ///   remove_relay(url)                      // ACT on stale check
    /// Without re-check after await, a lease acquired during suspension causes premature removal.
    func test_ephemeral_lease_toctou_before() {
        var leases: [String: Int] = ["relay1": 1]
        let storageLock = NSLock()
        let prematureRemoval = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Task A: release + check nil + "await" + act on stale check
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let newCount = (leases["relay1"] ?? 0) - 1
            leases["relay1"] = newCount == 0 ? nil : newCount
            let isNil = leases["relay1"] == nil  // CHECK: nil after release
            storageLock.unlock()
            barrier.arriveA()  // "await" suspension — Task B re-acquires
            // Master didn't re-check — acts on stale isNil
            if isNil {
                prematureRemoval.increment()  // Would remove relay!
            }
            group.leave()
        }

        // Task B: re-acquire during "await"
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()
            storageLock.lock()
            leases["relay1"] = (leases["relay1"] ?? 0) + 1  // Re-acquire
            storageLock.unlock()
            group.leave()
        }

        group.wait()
        XCTAssertEqual(prematureRemoval.value, 1, "Master RelayPool bug: stale nil check causes premature relay removal (TOCTOU across await)")
    }

    // MARK: - After fix: re-check lease after await prevents stale removal

    /// Simulation: RelayPool ephemeral lease management requires adding/removing
    /// real relay connections. The fix re-checks `guard ephemeralLeases[url] == nil`
    /// after the await point. This test reproduces the re-check-after-suspension pattern.
    func test_ephemeral_lease_toctou_after() {
        var leases: [String: Int] = [:]
        leases["relay1"] = 1
        let removed = AtomicCounter()
        let lock = NSLock()
        let barrier = ConcurrentBarrier()
        // Second sync: ensures B's re-acquire completes before A's re-check
        let bDone = DispatchSemaphore(value: 0)
        let group = DispatchGroup()

        // Thread A: release
        group.enter()
        DispatchQueue.global().async {
            lock.lock()
            let newCount = (leases["relay1"] ?? 0) - 1
            leases["relay1"] = newCount == 0 ? nil : newCount
            lock.unlock()

            barrier.arriveA()  // Signal: release done
            bDone.wait()       // Wait for B to re-acquire

            // Re-check after "await" — B has re-acquired, so lease is non-nil
            lock.lock()
            let shouldRemove = leases["relay1"] == nil
            lock.unlock()
            if shouldRemove {
                removed.increment()
            }
            group.leave()
        }

        // Thread B: acquire during "await"
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()  // Wait for A to release
            lock.lock()
            leases["relay1"] = (leases["relay1"] ?? 0) + 1
            lock.unlock()
            bDone.signal()     // Signal: re-acquire done
            group.leave()
        }

        group.wait()
        XCTAssertEqual(removed.value, 0, "Re-check prevents removal when lease re-acquired")
    }
}
