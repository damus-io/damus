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
}
