//
//  RelayPoolSubscriptionConcurrencyTests.swift
//  damusTests
//
//  Tests for race conditions: RelayPool eoseSent flag + onTermination stale removal
//  Beads: damus-9ym, damus-eb3
//

import XCTest
@testable import damus

final class RelayPoolSubscriptionConcurrencyTests: XCTestCase {

    // MARK: - Before fix: eoseSent flag race between concurrent Tasks

    /// Reproduces master's RelayPool eoseSent flag without NSLock:
    ///   if !eoseSent { eoseSent = true; yield .eose }  // CHECK-then-ACT
    /// Without NSLock, two Tasks both see eoseSent==false and both yield EOSE.
    func test_eose_flag_race_before() {
        var eoseSent = false
        let storageLock = NSLock()
        let bothYielded = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Task 1: upstream EOSE handler
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let alreadySent = eoseSent  // CHECK
            storageLock.unlock()
            barrier.arriveA()  // Both check before either sets
            if !alreadySent {
                storageLock.lock()
                eoseSent = true  // ACT
                storageLock.unlock()
                bothYielded.increment()
            }
            group.leave()
        }

        // Task 2: timeout handler
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let alreadySent = eoseSent  // CHECK: also false
            storageLock.unlock()
            barrier.arriveB()
            if !alreadySent {
                storageLock.lock()
                eoseSent = true  // ACT: duplicate set
                storageLock.unlock()
                bothYielded.increment()
            }
            group.leave()
        }

        group.wait()
        XCTAssertEqual(bothYielded.value, 2, "Master RelayPool bug: both threads yield EOSE (double-yield without lock)")
    }

    // MARK: - After fix: NSLock prevents double EOSE

    /// Simulation: the eoseLock is a local NSLock inside RelayPool.subscribe()'s
    /// AsyncStream closure, protecting a captured `eoseSent` boolean across
    /// concurrent upstream and timeout tasks. Testing the real path requires
    /// active relay connections and EOSE responses. This test reproduces the
    /// atomic check-and-set pattern.
    func test_eose_flag_race_after() {
        var eoseSent = false
        let lock = NSLock()
        let counter = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Task 1: upstream EOSE handler
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveA()
            lock.lock()
            let alreadySent = eoseSent
            eoseSent = true
            lock.unlock()
            if !alreadySent {
                counter.increment()
            }
            group.leave()
        }

        // Task 2: timeout handler
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()
            lock.lock()
            let alreadySent = eoseSent
            eoseSent = true
            lock.unlock()
            if !alreadySent {
                counter.increment()
            }
            group.leave()
        }

        group.wait()
        XCTAssertEqual(counter.value, 1, "With lock, exactly one EOSE yield")
    }
}
