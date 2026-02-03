//
//  NostrNetworkManagerConcurrencyTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-02.
//

import XCTest
import Dispatch
@testable import damus

/// Tests for NostrNetworkManager thread safety and continuation handling.
///
/// These tests verify that:
/// 1. Multiple concurrent awaitConnection() calls don't cause double-resume
/// 2. Timeout and connect() racing don't cause crashes
/// 3. The continuation dictionary properly synchronizes access
///
/// Run with Thread Sanitizer enabled for best results:
/// Edit Scheme → Test → Diagnostics → Thread Sanitizer
final class NostrNetworkManagerConcurrencyTests: XCTestCase {

    // MARK: - Continuation Dictionary Thread Safety Tests

    /// Tests that multiple concurrent awaitConnection() calls complete without crashes.
    ///
    /// This test spawns many concurrent tasks that all call awaitConnection(),
    /// then triggers connect() to resume them all. The test passes if no crashes
    /// or double-resume errors occur.
    func testAwaitConnection_ConcurrentCalls_NoDoublResume() async throws {
        // Create a test harness that isolates the continuation handling
        let harness = ConnectionContinuationTestHarness()

        let concurrentCallers = 50
        let expectation = XCTestExpectation(description: "All callers complete")
        expectation.expectedFulfillmentCount = concurrentCallers

        // Spawn many concurrent awaitConnection calls
        for _ in 0..<concurrentCallers {
            Task {
                await harness.awaitConnection(timeout: .seconds(5))
                expectation.fulfill()
            }
        }

        // Give tasks time to register their continuations
        try await Task.sleep(for: .milliseconds(100))

        // Trigger connect to resume all continuations
        await harness.connect()

        await fulfillment(of: [expectation], timeout: 10.0)
    }

    /// Tests that timeout and connect() racing doesn't cause double-resume.
    ///
    /// This test creates a scenario where timeout fires very close to when
    /// connect() is called, testing the race condition handling.
    func testAwaitConnection_TimeoutRacesWithConnect_NoDoubleResume() async throws {
        let harness = ConnectionContinuationTestHarness()

        let iterations = 20

        for _ in 0..<iterations {
            let expectation = XCTestExpectation(description: "Caller completes")

            // Start awaitConnection with very short timeout
            Task {
                await harness.awaitConnection(timeout: .milliseconds(10))
                expectation.fulfill()
            }

            // Immediately try to connect (racing with timeout)
            Task {
                await harness.connect()
            }

            await fulfillment(of: [expectation], timeout: 2.0)

            // Reset for next iteration
            await harness.reset()
        }
    }

    /// Stress test: runs concurrent access test many times to catch intermittent races.
    ///
    /// This test is designed to be run with Thread Sanitizer to catch data races
    /// that may not manifest as crashes.
    func testAwaitConnection_StressTest_ManyIterations() async throws {
        let iterations = 10
        let concurrentCallersPerIteration = 20

        for iteration in 0..<iterations {
            let harness = ConnectionContinuationTestHarness()
            let expectation = XCTestExpectation(description: "Iteration \(iteration)")
            expectation.expectedFulfillmentCount = concurrentCallersPerIteration

            // Spawn concurrent callers
            for _ in 0..<concurrentCallersPerIteration {
                Task {
                    await harness.awaitConnection(timeout: .seconds(2))
                    expectation.fulfill()
                }
            }

            // Random small delay before connect
            try await Task.sleep(for: .milliseconds(Int.random(in: 1...50)))

            await harness.connect()

            await fulfillment(of: [expectation], timeout: 5.0)
        }
    }

    /// Tests that already-connected state short-circuits correctly under concurrency.
    func testAwaitConnection_AlreadyConnected_ImmediateReturn() async throws {
        let harness = ConnectionContinuationTestHarness()

        // Connect first
        await harness.connect()

        // Now spawn many concurrent calls - they should all return immediately
        let concurrentCallers = 100
        let expectation = XCTestExpectation(description: "All callers complete immediately")
        expectation.expectedFulfillmentCount = concurrentCallers

        let startTime = Date()

        for _ in 0..<concurrentCallers {
            Task {
                await harness.awaitConnection(timeout: .seconds(5))
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        let elapsed = Date().timeIntervalSince(startTime)
        // Should complete very quickly since already connected
        XCTAssertLessThan(elapsed, 1.0, "Already-connected calls should return immediately")
    }
}

// MARK: - Test Harness

/// A test harness that isolates the continuation handling logic from NostrNetworkManager.
///
/// This allows us to test the thread-safety of the continuation dictionary
/// without needing to mock all the NostrNetworkManager dependencies.
/// Uses NSLock for thread safety, matching the actual implementation pattern.
private final class ConnectionContinuationTestHarness: @unchecked Sendable {
    /// Whether the harness is currently in a "connected" state.
    private var isConnected = false

    /// Pending continuations waiting for connection, keyed by request UUID.
    private var connectionContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Lock protecting `isConnected` and `connectionContinuations`.
    private let continuationsLock = NSLock()

    /// Asynchronously waits for the harness to become connected.
    ///
    /// If already connected, returns immediately. Otherwise, registers a
    /// continuation that will be resumed when `connect()` is called or
    /// when the timeout expires.
    ///
    /// - Parameter timeout: Maximum time to wait (default: 30 seconds).
    /// - Note: The continuation is stored in `connectionContinuations` and
    ///   removed atomically when resumed to prevent double-resume.
    func awaitConnection(timeout: Duration = .seconds(30)) async {
        // Short-circuit if already connected - check atomically inside lock
        let requestId = UUID()
        var timeoutTask: Task<Void, Never>?

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            continuationsLock.lock()
            if isConnected {
                continuationsLock.unlock()
                continuation.resume()
                return
            }
            connectionContinuations[requestId] = continuation
            continuationsLock.unlock()

            timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                self.resumeConnectionContinuation(requestId: requestId)
            }
        }

        timeoutTask?.cancel()
    }

    /// Resumes and removes the continuation for the given request UUID.
    ///
    /// Uses atomic remove-and-return to ensure the continuation is only
    /// resumed once, even if called concurrently from multiple threads.
    ///
    /// - Parameter requestId: The UUID of the request to resume.
    func resumeConnectionContinuation(requestId: UUID) {
        continuationsLock.lock()
        let continuation = connectionContinuations.removeValue(forKey: requestId)
        continuationsLock.unlock()

        continuation?.resume()
    }

    /// Marks the harness as connected and resumes all pending continuations.
    ///
    /// Sets `isConnected` to true, then atomically removes and resumes all
    /// waiting continuations. Future `awaitConnection()` calls will return
    /// immediately until `reset()` is called.
    func connect() {
        continuationsLock.lock()
        isConnected = true
        let continuations = connectionContinuations
        connectionContinuations.removeAll()
        continuationsLock.unlock()

        for (_, continuation) in continuations {
            continuation.resume()
        }
    }

    /// Resets the harness to disconnected state.
    ///
    /// Sets `isConnected` to false and clears any pending continuations
    /// (without resuming them). Use between test iterations to ensure
    /// clean state.
    func reset() {
        continuationsLock.lock()
        isConnected = false
        connectionContinuations.removeAll()
        continuationsLock.unlock()
    }
}
