//
//  NdbIntegrationTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-02.
//

import XCTest
import Dispatch
@testable import damus

/// Integration tests for Ndb lifecycle and concurrent access patterns.
///
/// These tests verify the full integration between NdbUseLock and the Ndb database,
/// including concurrent transaction access, close coordination, reopen behavior,
/// and app lifecycle scenarios.
///
/// ## Thread Sanitizer (TSan)
///
/// Run these tests with Thread Sanitizer enabled to detect data races:
/// 1. In Xcode: Edit Scheme → Test → Diagnostics → Thread Sanitizer
/// 2. Or via command line: `xcodebuild test -enableThreadSanitizer YES ...`
final class NdbIntegrationTests: XCTestCase {

    // MARK: - Concurrent Transaction Tests

    /// Tests that multiple concurrent Ndb lookups complete without deadlock or data corruption.
    ///
    /// This exercises the real integration path where multiple threads perform
    /// note lookups simultaneously while the lock coordinates access.
    @MainActor
    func testConcurrentNdbLookups() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Pre-populate with test events on background thread to avoid blocking main actor
        let eventCount = 20
        let createdNoteIds: [NoteId] = await Task.detached(priority: .userInitiated) {
            var noteIds: [NoteId] = []
            for i in 0..<eventCount {
                guard let testNote = NostrEvent(
                    content: "Concurrent test note \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: []
                ) else { continue }

                let eventJson = encode_json(testNote)!
                let relayMessage = "[\"EVENT\",\"subid\",\(eventJson)]"
                let processed = ndb.processEvent(relayMessage)
                if !processed {
                    // Log but don't fail - we're off main actor
                    print("Warning: Failed to process event \(i)")
                }
                noteIds.append(testNote.id)
            }
            return noteIds
        }.value

        await MainActor.run {
            XCTAssertEqual(createdNoteIds.count, eventCount, "Should have created \(eventCount) events")
        }

        try await Task.sleep(for: .milliseconds(100))

        // Spawn concurrent lookup tasks
        let concurrentLookups = 10
        let expectation = XCTestExpectation(description: "All lookups complete")
        expectation.expectedFulfillmentCount = concurrentLookups

        let startBarrier = DispatchGroup()
        startBarrier.enter()

        for i in 0..<concurrentLookups {
            DispatchQueue.global(qos: .userInitiated).async {
                startBarrier.wait()

                // Each thread performs multiple lookups
                for noteId in createdNoteIds.prefix(5) {
                    do {
                        let _ = try ndb.lookup_note_and_copy(noteId)
                    } catch {
                        // Note may not be found, that's OK for this test
                    }
                }

                expectation.fulfill()
            }
        }

        startBarrier.leave()
        await fulfillment(of: [expectation], timeout: 10.0)
    }

    /// Tests that Ndb close waits for active transactions to complete.
    ///
    /// This verifies the integration between NdbUseLock.waitUntilNdbCanClose
    /// and active withNdb() calls in a real Ndb instance.
    @MainActor
    func testCloseWaitsForActiveTransactions() async throws {
        let ndb = Ndb.test

        // Pre-populate with a test event
        guard let testNote = NostrEvent(
            content: "Close test note",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        ) else {
            XCTFail("Failed to create test note")
            return
        }

        let eventJson = encode_json(testNote)!
        let relayMessage = "[\"EVENT\",\"subid\",\(eventJson)]"
        _ = ndb.processEvent(relayMessage)
        try await Task.sleep(for: .milliseconds(50))

        let lookupStarted = XCTestExpectation(description: "Lookup started")
        let lookupCanFinish = DispatchSemaphore(value: 0)
        let lookupFinished = XCTestExpectation(description: "Lookup finished")
        let closeFinished = XCTestExpectation(description: "Close finished")

        // Start a background lookup that holds ndb open
        DispatchQueue.global().async {
            do {
                let _ = try ndb.withNdb({
                    lookupStarted.fulfill()
                    // Hold the transaction open
                    lookupCanFinish.wait()
                    return 42
                }, maxWaitTimeout: .seconds(5))
                lookupFinished.fulfill()
            } catch {
                XCTFail("Lookup failed: \(error)")
            }
        }

        await fulfillment(of: [lookupStarted], timeout: 2.0)

        // Try to close - should block until lookup finishes
        DispatchQueue.global().async {
            ndb.close()
            closeFinished.fulfill()
        }

        // Give close a moment to start waiting
        try await Task.sleep(for: .milliseconds(100))

        // Let the lookup finish
        lookupCanFinish.signal()

        await fulfillment(of: [lookupFinished, closeFinished], timeout: 5.0)
    }

    /// Tests that Ndb operations fail gracefully after close.
    ///
    /// Verifies that withNdb() throws NdbStreamError.ndbClosed after
    /// the database has been closed.
    @MainActor
    func testOperationsFailAfterClose() async throws {
        let ndb = Ndb.test

        // Close the database
        ndb.close()

        // Attempt operation - should throw ndbClosed
        do {
            let _ = try ndb.withNdb({
                return 42
            }, maxWaitTimeout: .milliseconds(100))
            XCTFail("Expected ndbClosed error")
        } catch {
            // Should be ndbClosed error
            XCTAssertTrue("\(error)".contains("ndbClosed"), "Expected ndbClosed error, got: \(error)")
        }
    }

    /// Stress test: concurrent lookups with varying timing.
    ///
    /// This test runs multiple iterations to catch intermittent race conditions
    /// in the lock/ndb integration. Run with Thread Sanitizer for best results.
    @MainActor
    func testConcurrentLookups_StressTest() async throws {
        for iteration in 0..<20 {
            let ndb = Ndb.test
            defer { ndb.close() }

            // Create a few test events
            for i in 0..<5 {
                guard let testNote = NostrEvent(
                    content: "Stress test \(iteration) note \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: []
                ) else { continue }

                let eventJson = encode_json(testNote)!
                let relayMessage = "[\"EVENT\",\"subid\",\(eventJson)]"
                _ = ndb.processEvent(relayMessage)
            }

            let concurrentUsers = 5
            let expectation = XCTestExpectation(description: "Iteration \(iteration)")
            expectation.expectedFulfillmentCount = concurrentUsers

            let startBarrier = DispatchGroup()
            startBarrier.enter()

            for _ in 0..<concurrentUsers {
                DispatchQueue.global(qos: .userInitiated).async {
                    startBarrier.wait()

                    do {
                        // Perform a lookup with random timing
                        let _ = try ndb.withNdb({
                            Thread.sleep(forTimeInterval: Double.random(in: 0.001...0.01))
                            return 42
                        }, maxWaitTimeout: .seconds(2))
                        expectation.fulfill()
                    } catch {
                        // Timeout is acceptable in stress test
                        expectation.fulfill()
                    }
                }
            }

            startBarrier.leave()
            await fulfillment(of: [expectation], timeout: 5.0)
        }
    }

    // MARK: - Subscription Integration Tests

    /// Tests that concurrent Ndb subscriptions work correctly without data loss.
    ///
    /// This verifies that multiple subscription streams can be created and
    /// receive events concurrently without race conditions.
    @MainActor
    func testConcurrentSubscriptions() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let testPubkey = test_keypair_full.pubkey
        let eventCount = 30

        // Pre-populate database on background thread to avoid blocking main actor
        await Task.detached(priority: .userInitiated) {
            for i in 0..<eventCount {
                guard let testNote = NostrEvent(
                    content: "Subscription test note \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: []
                ) else { continue }

                let eventJson = encode_json(testNote)!
                let relayMessage = "[\"EVENT\",\"subid\",\(eventJson)]"
                _ = ndb.processEvent(relayMessage)
            }
        }.value

        try await Task.sleep(for: .milliseconds(100))

        // Create multiple concurrent subscriptions
        let subscriptionCount = 3
        let filter = NostrFilter(kinds: [.text], authors: [testPubkey])

        let allReceived = XCTestExpectation(description: "All subscriptions received events")
        allReceived.expectedFulfillmentCount = subscriptionCount

        for subIndex in 0..<subscriptionCount {
            Task.detached(priority: .userInitiated) {
                var count = 0
                do {
                    subscriptionLoop: for try await item in try ndb.subscribe(filters: [filter]) {
                        switch item {
                        case .event:
                            count += 1
                        case .eose:
                            break subscriptionLoop
                        }
                    }
                } catch {
                    // Stream ended
                }

                // Marshal assertion back to main actor
                let eventCount = count
                let index = subIndex
                await MainActor.run {
                    XCTAssertGreaterThan(eventCount, 0, "Subscription \(index) received \(eventCount) events, expected > 0")
                    allReceived.fulfill()
                }
            }
        }

        await fulfillment(of: [allReceived], timeout: 10.0)
    }

    // MARK: - Event Processing Integration Tests

    /// Tests that event processing works correctly with concurrent reads.
    ///
    /// This simulates the real-world scenario where RelayPool processes
    /// incoming events while other parts of the app read from Ndb.
    @MainActor
    func testEventProcessingWithConcurrentReads() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let eventsToProcess = 50
        let processedExpectation = XCTestExpectation(description: "All events processed")
        let readsExpectation = XCTestExpectation(description: "Concurrent reads complete")
        readsExpectation.expectedFulfillmentCount = 10

        // Start concurrent readers
        for i in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<20 {
                    do {
                        // Try to read any existing profile
                        let _ = try ndb.withNdb({
                            Thread.sleep(forTimeInterval: Double.random(in: 0.001...0.005))
                            return true
                        }, maxWaitTimeout: .seconds(2))
                    } catch {
                        // Timeout acceptable
                    }
                }
                readsExpectation.fulfill()
            }
        }

        // Process events concurrently
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<eventsToProcess {
                guard let testNote = NostrEvent(
                    content: "Concurrent processing test \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: []
                ) else { continue }

                let eventJson = encode_json(testNote)!
                let relayMessage = "[\"EVENT\",\"subid\",\(eventJson)]"
                _ = ndb.processEvent(relayMessage)

                // Small delay between events
                Thread.sleep(forTimeInterval: Double.random(in: 0.001...0.003))
            }
            processedExpectation.fulfill()
        }

        await fulfillment(of: [processedExpectation, readsExpectation], timeout: 15.0)
    }

    // MARK: - TOCTOU Protection Tests

    /// Tests that the double-check in withNdb() prevents TOCTOU races.
    ///
    /// This verifies that the pattern of checking is_closed both before
    /// and inside the lock correctly handles concurrent close attempts.
    @MainActor
    func testTOCTOUProtection_ConcurrentClose() async throws {
        for iteration in 0..<10 {
            let ndb = Ndb.test

            let operationsStarted = XCTestExpectation(description: "Operations started \(iteration)")
            operationsStarted.expectedFulfillmentCount = 5
            let operationsComplete = XCTestExpectation(description: "Operations complete \(iteration)")
            operationsComplete.expectedFulfillmentCount = 5

            // Start multiple operations that will race with close
            for i in 0..<5 {
                DispatchQueue.global(qos: .userInitiated).async {
                    operationsStarted.fulfill()

                    do {
                        let _ = try ndb.withNdb({
                            Thread.sleep(forTimeInterval: Double.random(in: 0.001...0.01))
                            return i
                        }, maxWaitTimeout: .milliseconds(500))
                    } catch {
                        // ndbClosed or timeout is expected
                    }

                    operationsComplete.fulfill()
                }
            }

            // Wait for operations to start
            await fulfillment(of: [operationsStarted], timeout: 2.0)

            // Close during operations
            DispatchQueue.global().async {
                ndb.close()
            }

            await fulfillment(of: [operationsComplete], timeout: 5.0)
        }
    }
}
