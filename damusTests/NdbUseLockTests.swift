//
//  NdbUseLockTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-02.
//

import XCTest
import Dispatch
@testable import damus

/// Tests for NdbUseLock thread safety and blocking behavior.
///
/// These tests verify that:
/// 1. The lock mechanisms work correctly under concurrent access
/// 2. No deadlocks occur when multiple threads access the lock
/// 3. Blocking behavior doesn't cause excessive thread starvation
///
/// ## Thread Sanitizer (TSan)
///
/// These tests are designed to be run with Thread Sanitizer enabled to detect data races.
/// To enable TSan:
/// 1. In Xcode: Edit Scheme → Test → Diagnostics → Thread Sanitizer
/// 2. Or via command line: `xcodebuild test -enableThreadSanitizer YES ...`
///
/// Run the stress tests with TSan to catch intermittent race conditions that may not
/// manifest in a single test run.
final class NdbUseLockTests: XCTestCase {

    // MARK: - FallbackUseLock Basic Tests (iOS < 18)

    /// Tests that FallbackUseLock correctly handles a simple open/use/close cycle.
    func testFallbackUseLock_BasicOpenUseClose() throws {
        let lock = Ndb.FallbackUseLock()

        // Mark ndb as open
        lock.markNdbOpen()

        // Use ndb
        let result = try lock.keepNdbOpen(during: {
            return 42
        }, maxWaitTimeout: .milliseconds(500))

        XCTAssertEqual(result, 42)

        // Close ndb
        var closeCalled = false
        try lock.waitUntilNdbCanClose(thenClose: {
            closeCalled = true
            return false // ndb is now closed
        }, maxTimeout: .milliseconds(500))

        XCTAssertTrue(closeCalled)
    }

    /// Tests that timeout works correctly when ndb is not open.
    func testFallbackUseLock_Timeout_WhenNdbNotOpen() {
        let lock = Ndb.FallbackUseLock()
        // Don't call markNdbOpen() - ndb is closed

        let startTime = Date()

        XCTAssertThrowsError(try lock.keepNdbOpen(during: {
            return 42
        }, maxWaitTimeout: .milliseconds(100))) { error in
            // Should timeout
            let elapsed = Date().timeIntervalSince(startTime)
            XCTAssertGreaterThan(elapsed, 0.05) // At least 50ms
            XCTAssertLessThan(elapsed, 0.5) // But not too long
        }
    }

    /// Tests that markNdbOpen is safe when called multiple times.
    func testFallbackUseLock_MarkNdbOpenIdempotence() throws {
        let lock = Ndb.FallbackUseLock()

        // Call markNdbOpen multiple times
        for _ in 0..<10 {
            lock.markNdbOpen()
        }

        // Should still work normally
        let result = try lock.keepNdbOpen(during: { return 42 }, maxWaitTimeout: .seconds(1))
        XCTAssertEqual(result, 42)

        // And close should work
        var closeCalled = false
        try lock.waitUntilNdbCanClose(thenClose: {
            closeCalled = true
            return false
        }, maxTimeout: .seconds(1))
        XCTAssertTrue(closeCalled)
    }

    /// Tests behavior when keepNdbOpen is called with deadline already passed.
    ///
    /// This tests the edge case where remaining <= 0 at entry.
    func testFallbackUseLock_DeadlinePassedAtEntry() throws {
        let lock = Ndb.FallbackUseLock()
        // Don't open - force timeout path

        // Use extremely short timeout
        let startTime = Date()
        XCTAssertThrowsError(try lock.keepNdbOpen(during: {
            return 42
        }, maxWaitTimeout: .nanoseconds(1))) { error in
            let elapsed = Date().timeIntervalSince(startTime)
            // Should fail very quickly (< 100ms)
            XCTAssertLessThan(elapsed, 0.1, "Zero timeout should fail immediately")
        }

        // Also test with .never equivalent
        XCTAssertThrowsError(try lock.keepNdbOpen(during: {
            return 42
        }, maxWaitTimeout: .milliseconds(0))) { _ in
            // Just verify it throws
        }
    }

    // MARK: - FallbackUseLock Concurrency Tests (iOS < 18)

    /// Tests that multiple concurrent users can access ndb without deadlock.
    ///
    /// This test verifies that when multiple threads try to use ndb simultaneously,
    /// they don't deadlock due to the lock being held while waiting on the semaphore.
    func testFallbackUseLock_ConcurrentAccess_NoDeadlock() throws {
        let lock = Ndb.FallbackUseLock()
        lock.markNdbOpen()

        let concurrentUsers = 10
        let expectation = XCTestExpectation(description: "All users complete")
        expectation.expectedFulfillmentCount = concurrentUsers

        let startBarrier = DispatchGroup()
        startBarrier.enter()

        // Spawn multiple concurrent users
        for i in 0..<concurrentUsers {
            DispatchQueue.global(qos: .userInitiated).async {
                startBarrier.wait() // Wait for all threads to be ready

                do {
                    let result = try lock.keepNdbOpen(during: {
                        // Simulate some work
                        Thread.sleep(forTimeInterval: 0.01)
                        return i
                    }, maxWaitTimeout: .seconds(5))

                    XCTAssertEqual(result, i)
                    expectation.fulfill()
                } catch {
                    XCTFail("Thread \(i) failed with error: \(error)")
                }
            }
        }

        // Release all threads at once
        startBarrier.leave()

        wait(for: [expectation], timeout: 10.0)
    }

    /// Tests that the lock doesn't cause excessive blocking when threads contend.
    ///
    /// This test measures the time taken for concurrent operations to complete.
    /// If the lock causes excessive blocking (holding lock while waiting on semaphore),
    /// the total time will be much higher than expected.
    func testFallbackUseLock_BlockingBehavior_ReasonableTime() throws {
        let lock = Ndb.FallbackUseLock()
        lock.markNdbOpen()

        let concurrentUsers = 5
        let workDuration: TimeInterval = 0.05 // 50ms per operation
        let expectation = XCTestExpectation(description: "All users complete")
        expectation.expectedFulfillmentCount = concurrentUsers

        let startTime = Date()
        let completionTimes = UnsafeMutablePointer<TimeInterval>.allocate(capacity: concurrentUsers)
        completionTimes.initialize(repeating: 0, count: concurrentUsers)
        defer { completionTimes.deinitialize(count: concurrentUsers); completionTimes.deallocate() }

        let startBarrier = DispatchGroup()
        startBarrier.enter()

        for i in 0..<concurrentUsers {
            DispatchQueue.global(qos: .userInitiated).async {
                startBarrier.wait()

                do {
                    _ = try lock.keepNdbOpen(during: {
                        Thread.sleep(forTimeInterval: workDuration)
                        return i
                    }, maxWaitTimeout: .seconds(10))

                    completionTimes[i] = Date().timeIntervalSince(startTime)
                    expectation.fulfill()
                } catch {
                    XCTFail("Thread \(i) failed: \(error)")
                }
            }
        }

        startBarrier.leave()
        wait(for: [expectation], timeout: 30.0)

        let maxCompletionTime = (0..<concurrentUsers).map { completionTimes[$0] }.max() ?? 0

        // With proper lock implementation, concurrent access should be allowed
        // after the first user acquires the semaphore. Total time should be
        // roughly: first_wait + max(all_work_durations) which is about 2x workDuration
        // With the bug (lock held during wait), it would be: N * workDuration

        // Allow some overhead but flag if it takes way too long
        let reasonableMaxTime = workDuration * Double(concurrentUsers) * 0.75

        // Assert that blocking is not serialized - concurrent users should complete faster
        XCTAssertLessThan(maxCompletionTime, reasonableMaxTime,
            "Blocking appears serialized: max=\(maxCompletionTime)s threshold=\(reasonableMaxTime)s")
    }

    /// Tests close waits for all users to finish.
    func testFallbackUseLock_CloseWaitsForUsers() throws {
        let lock = Ndb.FallbackUseLock()
        lock.markNdbOpen()

        let userStarted = XCTestExpectation(description: "User started")
        // Use DispatchSemaphore instead of XCTestExpectation to avoid calling
        // self.wait from a background thread, which is prone to XCTest flakiness.
        let userCanFinish = DispatchSemaphore(value: 0)
        let userFinished = XCTestExpectation(description: "User finished")
        let closeStarted = XCTestExpectation(description: "Close started")
        let closeCompleted = XCTestExpectation(description: "Close completed")

        // Start a user that holds ndb open
        DispatchQueue.global().async {
            do {
                _ = try lock.keepNdbOpen(during: {
                    userStarted.fulfill()
                    // Wait until test signals us to finish
                    userCanFinish.wait()
                    return 1
                }, maxWaitTimeout: .seconds(5))
                userFinished.fulfill()
            } catch {
                XCTFail("User failed: \(error)")
            }
        }

        // Wait for user to start
        wait(for: [userStarted], timeout: 2.0)

        // Try to close - should wait for user
        DispatchQueue.global().async {
            do {
                closeStarted.fulfill()
                try lock.waitUntilNdbCanClose(thenClose: {
                    return false
                }, maxTimeout: .seconds(5))
                closeCompleted.fulfill()
            } catch {
                XCTFail("Close failed: \(error)")
            }
        }

        // Wait for close attempt to start (non-blocking replacement for Thread.sleep)
        wait(for: [closeStarted], timeout: 2.0)

        // Let the user finish
        userCanFinish.signal()

        // Both should complete
        wait(for: [userFinished, closeCompleted], timeout: 5.0)
    }
}
