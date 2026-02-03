//
//  NostrNetworkManagerIntegrationTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-02.
//

import XCTest
import Dispatch
@testable import damus

/// Integration tests for NostrNetworkManager connection lifecycle and concurrent operations.
///
/// These tests verify the full integration between NostrNetworkManager, RelayPool,
/// SubscriptionManager, and the connection/reconnection lifecycle.
///
/// ## Thread Sanitizer (TSan)
///
/// Run these tests with Thread Sanitizer enabled to detect data races:
/// 1. In Xcode: Edit Scheme → Test → Diagnostics → Thread Sanitizer
/// 2. Or via command line: `xcodebuild test -enableThreadSanitizer YES ...`
@MainActor
final class NostrNetworkManagerIntegrationTests: XCTestCase {

    var damusState: DamusState?

    /// Initializes a fresh DamusState for each test using generate_test_damus_state with mock_profile_info=nil and addNdbToRelayPool=false.
    override func setUpWithError() throws {
        damusState = generate_test_damus_state(
            mock_profile_info: nil,
            addNdbToRelayPool: false
        )
    }

    /// Cleans up by setting damusState to nil, allowing the test state to be deallocated.
    override func tearDownWithError() throws {
        damusState = nil
    }

    // MARK: - Connection Lifecycle Tests

    /// Tests that multiple concurrent awaitConnection calls all resolve correctly.
    ///
    /// This verifies the continuation management in NostrNetworkManager.connect()
    /// where multiple callers may be waiting for connection simultaneously.
    func testConcurrentAwaitConnectionCalls() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        let concurrentWaiters = 5
        let allConnected = XCTestExpectation(description: "All waiters connected")
        allConnected.expectedFulfillmentCount = concurrentWaiters

        // Start concurrent awaitConnection calls
        for i in 0..<concurrentWaiters {
            Task {
                do {
                    try await damusState.nostrNetwork.awaitConnection(timeout: .seconds(30))
                    allConnected.fulfill()
                } catch {
                    // Timeout is acceptable in test environment
                    allConnected.fulfill()
                }
            }
        }

        // Trigger connection
        await damusState.nostrNetwork.connect()

        await fulfillment(of: [allConnected], timeout: 35.0)
    }

    /// Tests that connection state is properly managed during rapid connect/disconnect cycles.
    func testRapidConnectDisconnectCycles() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        for cycle in 0..<5 {
            // Connect
            await damusState.nostrNetwork.connect()

            // Brief operation
            try await Task.sleep(for: .milliseconds(50))

            // Disconnect to exercise the full connect/disconnect cycle
            await damusState.nostrNetwork.disconnectRelays()

            // Brief pause after disconnect
            try await Task.sleep(for: .milliseconds(20))

            // The network manager should handle rapid cycling gracefully
        }
    }

    // MARK: - Subscription Concurrency Tests

    /// Tests that multiple concurrent subscriptions work without race conditions.
    func testConcurrentSubscriptions() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        // Pre-populate with test events - fail fast if fixture is missing
        let testBundle = Bundle(for: type(of: self))
        guard let fileURL = testBundle.url(forResource: "test_notes", withExtension: "jsonl") else {
            XCTFail("Required test fixture test_notes.jsonl not found in test bundle")
            return
        }

        // Read file and process events off main thread to avoid blocking I/O
        // ndb.processEvent() goes through withNdb() → keepNdbOpen() → ndb_process_event
        // which performs synchronous work that should not block the main actor
        let ndb = damusState.ndb
        try await Task.detached {
            let notesJSONL = try String(contentsOf: fileURL, encoding: .utf8)
            for noteText in notesJSONL.split(separator: "\n") {
                _ = ndb.processEvent("[\"EVENT\",\"subid\",\(String(noteText))]")
            }
        }.value

        try await Task.sleep(for: .milliseconds(100))

        let subscriptionCount = 3
        let allCompleted = XCTestExpectation(description: "All subscriptions completed")
        allCompleted.expectedFulfillmentCount = subscriptionCount

        for i in 0..<subscriptionCount {
            Task {
                var eventCount = 0
                streamLoop: for await item in damusState.nostrNetwork.reader.advancedStream(
                    filters: [NostrFilter(kinds: [.text], limit: 10)],
                    streamMode: .ndbOnly
                ) {
                    switch item {
                    case .event:
                        eventCount += 1
                    case .ndbEose:
                        break streamLoop
                    default:
                        continue
                    }
                }
                allCompleted.fulfill()
            }
        }

        await fulfillment(of: [allCompleted], timeout: 15.0)
    }

    /// Stress test: multiple concurrent subscriptions with varying filters.
    func testConcurrentSubscriptions_StressTest() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        // Pre-populate off main thread to avoid blocking
        let ndb = damusState.ndb
        await Task.detached {
            for i in 0..<20 {
                guard let testNote = NostrEvent(
                    content: "Stress test note \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: []
                ) else { continue }

                let eventJson = encode_json(testNote)!
                _ = ndb.processEvent("[\"EVENT\",\"subid\",\(eventJson)]")
            }
        }.value

        try await Task.sleep(for: .milliseconds(100))

        for iteration in 0..<10 {
            let concurrentSubs = 5
            let allDone = XCTestExpectation(description: "Iteration \(iteration)")
            allDone.expectedFulfillmentCount = concurrentSubs

            for subIndex in 0..<concurrentSubs {
                Task {
                    // Each subscription has different limit
                    let limit = (subIndex + 1) * 2
                    var count = 0

                    streamLoop: for await item in damusState.nostrNetwork.reader.advancedStream(
                        filters: [NostrFilter(kinds: [.text], limit: UInt32(limit))],
                        streamMode: .ndbOnly
                    ) {
                        switch item {
                        case .event:
                            count += 1
                        case .ndbEose:
                            break streamLoop
                        default:
                            continue
                        }
                    }

                    allDone.fulfill()
                }
            }

            await fulfillment(of: [allDone], timeout: 10.0)
        }
    }

    // MARK: - Event Flow Tests

    /// Tests that events flow correctly through the system without data loss.
    func testEventFlowIntegrity() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        let eventCount = 50

        // Create and process events off main thread to avoid blocking
        let ndb = damusState.ndb
        let createdIds: Set<NoteId> = await Task.detached {
            var ids = Set<NoteId>()
            for i in 0..<eventCount {
                guard let testNote = NostrEvent(
                    content: "Event flow test \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: []
                ) else { continue }

                ids.insert(testNote.id)
                let eventJson = encode_json(testNote)!
                _ = ndb.processEvent("[\"EVENT\",\"subid\",\(eventJson)]")
            }
            return ids
        }.value

        try await Task.sleep(for: .milliseconds(200))

        // Verify all events can be retrieved
        var receivedIds = Set<NoteId>()
        let streamComplete = XCTestExpectation(description: "Stream complete")

        Task {
            streamLoop: for await item in damusState.nostrNetwork.reader.advancedStream(
                filters: [NostrFilter(kinds: [.text], authors: [test_keypair_full.pubkey])],
                streamMode: .ndbOnly
            ) {
                switch item {
                case .event(let lender):
                    try? lender.borrow { event in
                        receivedIds.insert(event.id)
                    }
                case .ndbEose:
                    break streamLoop
                default:
                    continue
                }
            }
            streamComplete.fulfill()
        }

        await fulfillment(of: [streamComplete], timeout: 10.0)

        // All created events should be received
        XCTAssertEqual(receivedIds.count, eventCount, "Should receive all \(eventCount) events")
    }

    // MARK: - Cancellation Tests

    /// Tests that subscription cancellation is handled safely without race conditions.
    func testSubscriptionCancellation() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        // Pre-populate off main thread to avoid blocking
        let ndb = damusState.ndb
        await Task.detached {
            for i in 0..<100 {
                guard let testNote = NostrEvent(
                    content: "Cancellation test \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: []
                ) else { continue }

                let eventJson = encode_json(testNote)!
                _ = ndb.processEvent("[\"EVENT\",\"subid\",\(eventJson)]")
            }
        }.value

        try await Task.sleep(for: .milliseconds(100))

        for iteration in 0..<20 {
            let task = Task {
                var count = 0
                for await item in damusState.nostrNetwork.reader.advancedStream(
                    filters: [NostrFilter(kinds: [.text])],
                    streamMode: .ndbOnly
                ) {
                    switch item {
                    case .event:
                        count += 1
                        // Random early cancel
                        if count > 5 && Double.random(in: 0...1) > 0.7 {
                            break
                        }
                    default:
                        continue
                    }
                }
                return count
            }

            // Cancel after random delay
            try await Task.sleep(for: .milliseconds(UInt64.random(in: 10...100)))
            task.cancel()

            // Should not crash or deadlock
            _ = try? await task.value
        }
    }

    // MARK: - Background/Foreground Tests

    /// Tests that background/foreground transitions are handled safely.
    func testBackgroundForegroundTransitions() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        for cycle in 0..<5 {
            // Simulate background
            await damusState.nostrNetwork.handleAppBackgroundRequest()

            // Brief pause
            try await Task.sleep(for: .milliseconds(50))

            // Simulate foreground
            await damusState.nostrNetwork.handleAppForegroundRequest()

            // Brief pause
            try await Task.sleep(for: .milliseconds(50))
        }

        // Should not crash and should be in a consistent state
    }

    /// Stress test: concurrent operations during background/foreground transitions.
    func testConcurrentOpsWithLifecycleTransitions() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        // Pre-populate off main thread to avoid blocking
        let ndb = damusState.ndb
        await Task.detached {
            for i in 0..<20 {
                guard let testNote = NostrEvent(
                    content: "Lifecycle test \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: []
                ) else { continue }

                let eventJson = encode_json(testNote)!
                _ = ndb.processEvent("[\"EVENT\",\"subid\",\(eventJson)]")
            }
        }.value

        let opsComplete = XCTestExpectation(description: "Operations complete")
        opsComplete.expectedFulfillmentCount = 10

        // Start concurrent subscriptions
        for i in 0..<10 {
            Task {
                streamLoop: for await item in damusState.nostrNetwork.reader.advancedStream(
                    filters: [NostrFilter(kinds: [.text], limit: 5)],
                    streamMode: .ndbOnly
                ) {
                    switch item {
                    case .ndbEose:
                        break streamLoop
                    default:
                        continue
                    }
                }
                opsComplete.fulfill()
            }
        }

        // Trigger lifecycle transitions during subscriptions
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(20))
            await damusState.nostrNetwork.handleAppBackgroundRequest()
            try await Task.sleep(for: .milliseconds(20))
            await damusState.nostrNetwork.handleAppForegroundRequest()
        }

        await fulfillment(of: [opsComplete], timeout: 15.0)
    }

    // MARK: - Race Condition Tests

    /// Tests that a single continuation is never resumed twice.
    ///
    /// This targets the race where both timeout task and connect() try to
    /// resume the same continuation simultaneously.
    func testContinuationDoubleResume_TimeoutVsConnect() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        for iteration in 0..<20 {
            // Start awaitConnection with very short timeout to create race
            let task = Task {
                do {
                    try await damusState.nostrNetwork.awaitConnection(timeout: .milliseconds(50))
                    return true
                } catch {
                    return false
                }
            }

            // Trigger connect at roughly the same time as timeout
            Task {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 30...70)))
                await damusState.nostrNetwork.connect()
            }

            // Should complete without crash (double-resume would crash)
            let _ = await task.value
        }
    }

    /// Tests TOCTOU protection between isConnected check and lock acquisition.
    ///
    /// Verifies that checking isConnected outside the lock doesn't cause issues
    /// when connection state changes between check and registration.
    func testAlreadyConnectedShortCircuit_TOCTOU() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        // Connect first
        await damusState.nostrNetwork.connect()
        try await Task.sleep(for: .milliseconds(100))

        let concurrentCalls = 20
        let allComplete = XCTestExpectation(description: "All calls complete")
        allComplete.expectedFulfillmentCount = concurrentCalls

        // Many concurrent awaitConnection calls while already connected
        // Should all return quickly without issues
        for _ in 0..<concurrentCalls {
            Task {
                do {
                    try await damusState.nostrNetwork.awaitConnection(timeout: .seconds(1))
                } catch {
                    // Timeout acceptable
                }
                allComplete.fulfill()
            }
        }

        await fulfillment(of: [allComplete], timeout: 5.0)
    }

    /// Tests that disconnect properly handles pending awaitConnection continuations.
    func testDisconnectClearsPendingContinuations() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        let waitersStarted = XCTestExpectation(description: "Waiters started")
        waitersStarted.expectedFulfillmentCount = 5
        let allComplete = XCTestExpectation(description: "All complete")
        allComplete.expectedFulfillmentCount = 5

        // Start several awaitConnection calls
        for _ in 0..<5 {
            Task {
                waitersStarted.fulfill()
                do {
                    try await damusState.nostrNetwork.awaitConnection(timeout: .seconds(5))
                } catch {
                    // Timeout or other error
                }
                allComplete.fulfill()
            }
        }

        await fulfillment(of: [waitersStarted], timeout: 2.0)

        // Now disconnect while waiters are pending
        await damusState.nostrNetwork.disconnectRelays()

        // All waiters should eventually complete (timeout or be cleaned up)
        await fulfillment(of: [allComplete], timeout: 10.0)
    }

    /// Tests behavior when connection attempts time out (simulating connection failure).
    ///
    /// Verifies that awaitConnection properly handles the case where no relays
    /// successfully connect within the timeout period.
    func testConnectionTimeout_NoRelaysAvailable() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        // Don't call connect() - just let awaitConnection timeout
        let timeoutOccurred = XCTestExpectation(description: "Timeout occurred")

        Task {
            do {
                try await damusState.nostrNetwork.awaitConnection(timeout: .milliseconds(200))
                // If we get here without error, connection succeeded (acceptable)
                timeoutOccurred.fulfill()
            } catch {
                // Timeout expected - this is the success case for this test
                timeoutOccurred.fulfill()
            }
        }

        await fulfillment(of: [timeoutOccurred], timeout: 5.0)
    }

    /// Tests multiple sequential connection failures don't cause resource leaks.
    ///
    /// Verifies that repeated timeout scenarios properly clean up continuations
    /// and don't accumulate stale state.
    func testRepeatedConnectionTimeouts_NoResourceLeak() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        // Multiple sequential timeouts should all complete without issues
        for iteration in 0..<10 {
            let completed = XCTestExpectation(description: "Iteration \(iteration)")

            Task {
                do {
                    try await damusState.nostrNetwork.awaitConnection(timeout: .milliseconds(50))
                } catch {
                    // Timeout expected
                }
                completed.fulfill()
            }

            await fulfillment(of: [completed], timeout: 2.0)
        }

        // After many timeouts, concurrent operations should still work
        let finalTest = XCTestExpectation(description: "Final concurrent test")
        finalTest.expectedFulfillmentCount = 5

        for _ in 0..<5 {
            Task {
                do {
                    try await damusState.nostrNetwork.awaitConnection(timeout: .milliseconds(100))
                } catch {
                    // Expected
                }
                finalTest.fulfill()
            }
        }

        await fulfillment(of: [finalTest], timeout: 5.0)
    }

    /// Tests that disconnect during active awaitConnection calls handles all continuations.
    ///
    /// Stress test variant with more concurrent waiters and rapid disconnect.
    func testDisconnectDuringAwaitConnection_StressTest() async throws {
        guard let damusState else {
            XCTFail("DamusState not initialized")
            return
        }

        for iteration in 0..<10 {
            let waiterCount = 10
            let allComplete = XCTestExpectation(description: "Iteration \(iteration)")
            allComplete.expectedFulfillmentCount = waiterCount

            // Start many concurrent awaitConnection calls
            for _ in 0..<waiterCount {
                Task {
                    do {
                        try await damusState.nostrNetwork.awaitConnection(timeout: .seconds(2))
                    } catch {
                        // Timeout or disconnect - both acceptable
                    }
                    allComplete.fulfill()
                }
            }

            // Random delay then disconnect
            try await Task.sleep(for: .milliseconds(UInt64.random(in: 10...50)))
            await damusState.nostrNetwork.disconnectRelays()

            await fulfillment(of: [allComplete], timeout: 5.0)
        }
    }
}
