//
//  WalletModelConcurrencyTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-02.
//

import XCTest
import Dispatch
@testable import damus

/// Tests for WalletModel thread safety and continuation handling.
///
/// These tests verify that:
/// 1. Multiple concurrent wallet requests don't cause double-resume
/// 2. The continuations dictionary properly synchronizes access
/// 3. Concurrent resume calls with the same requestId don't crash
///
/// Run with Thread Sanitizer enabled for best results:
/// Edit Scheme → Test → Diagnostics → Thread Sanitizer
final class WalletModelConcurrencyTests: XCTestCase {

    // MARK: - Continuation Dictionary Thread Safety Tests

    /// Tests that multiple concurrent resume calls for the same request ID
    /// don't cause a double-resume crash.
    ///
    /// This simulates the race where both a timeout and a response try to
    /// resume the same continuation.
    func testResume_ConcurrentCallsSameId_NoDoubleResume() async throws {
        let iterations = 50

        for iteration in 0..<iterations {
            // Use a fresh harness per iteration to ensure clean state
            let harness = WalletContinuationTestHarness()

            // Create a unique request ID per iteration
            var bytes = [UInt8](repeating: 0, count: 32)
            bytes[0] = UInt8(iteration % 256)
            bytes[1] = UInt8(iteration / 256)
            let requestId = NoteId(Data(bytes))

            // Register a continuation
            let expectation = XCTestExpectation(description: "Continuation resumed iteration \(iteration)")

            Task {
                do {
                    _ = try await harness.waitForResponse(for: requestId, timeout: .seconds(5))
                    expectation.fulfill()
                } catch {
                    // Timeout or error is acceptable in this race test
                    expectation.fulfill()
                }
            }

            // Give time for continuation to register
            try await Task.sleep(for: .milliseconds(10))

            // Now race multiple resume calls
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<10 {
                    group.addTask {
                        if i % 2 == 0 {
                            harness.resumeWithResult(request: requestId)
                        } else {
                            harness.resumeWithError(request: requestId)
                        }
                    }
                }
            }

            await fulfillment(of: [expectation], timeout: 2.0)
        }
    }

    /// Tests that many concurrent waitForResponse calls don't interfere with each other.
    func testWaitForResponse_ManyConcurrentRequests_AllComplete() async throws {
        let harness = WalletContinuationTestHarness()

        let concurrentRequests = 30
        let expectation = XCTestExpectation(description: "All requests complete")
        expectation.expectedFulfillmentCount = concurrentRequests

        var requestIds: [NoteId] = []
        let requestIdsLock = NSLock()

        // Spawn many concurrent waitForResponse calls with unique IDs
        for i in 0..<concurrentRequests {
            Task {
                // Create a unique request ID by using index as part of the bytes
                var bytes = [UInt8](repeating: 0, count: 32)
                bytes[0] = UInt8(i % 256)
                bytes[1] = UInt8(i / 256)
                let requestId = NoteId(Data(bytes))

                requestIdsLock.lock()
                requestIds.append(requestId)
                requestIdsLock.unlock()

                do {
                    _ = try await harness.waitForResponse(for: requestId, timeout: .seconds(5))
                    expectation.fulfill()
                } catch {
                    XCTFail("Request \(i) failed unexpectedly: \(error)")
                    expectation.fulfill()
                }
            }
        }

        // Give time for all continuations to register
        try await Task.sleep(for: .milliseconds(100))

        // Resume all of them concurrently
        requestIdsLock.lock()
        let ids = requestIds
        requestIdsLock.unlock()

        await withTaskGroup(of: Void.self) { group in
            for requestId in ids {
                group.addTask {
                    harness.resumeWithResult(request: requestId)
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 10.0)
    }

    /// Stress test: runs concurrent access patterns many times.
    func testContinuations_StressTest_ManyIterations() async throws {
        let iterations = 20
        let requestsPerIteration = 10

        for iteration in 0..<iterations {
            let harness = WalletContinuationTestHarness()
            let expectation = XCTestExpectation(description: "Iteration \(iteration) complete")
            expectation.expectedFulfillmentCount = requestsPerIteration

            var requestIds: [NoteId] = []

            for i in 0..<requestsPerIteration {
                var bytes = [UInt8](repeating: UInt8.random(in: 0...255), count: 32)
                bytes[0] = UInt8(i)
                bytes[1] = UInt8(iteration % 256)
                let requestId = NoteId(Data(bytes))
                requestIds.append(requestId)

                Task {
                    do {
                        _ = try await harness.waitForResponse(for: requestId, timeout: .seconds(2))
                        expectation.fulfill()
                    } catch {
                        // Timeout acceptable in stress test
                        expectation.fulfill()
                    }
                }
            }

            // Random delay before resuming
            try await Task.sleep(for: .milliseconds(Int.random(in: 1...30)))

            // Resume in random order
            for requestId in requestIds.shuffled() {
                harness.resumeWithResult(request: requestId)
            }

            await fulfillment(of: [expectation], timeout: 5.0)
        }
    }

    /// Tests timeout behavior doesn't leave stale continuations.
    func testWaitForResponse_Timeout_CleansUpContinuation() async throws {
        let harness = WalletContinuationTestHarness()

        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[0] = 42
        let requestId = NoteId(Data(bytes))

        let expectation = XCTestExpectation(description: "Timeout occurred")

        Task {
            do {
                _ = try await harness.waitForResponse(for: requestId, timeout: .milliseconds(50))
                XCTFail("Should have timed out")
            } catch {
                // Expected timeout
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        // Verify late resume doesn't crash (continuation should be cleaned up)
        harness.resumeWithResult(request: requestId)
    }
}

// MARK: - Test Harness

/// A test harness that isolates the continuation handling logic from WalletModel.
///
/// This replicates the fixed pattern from WalletModel to test thread-safety
/// without needing the full WalletModel dependencies. It stores both the
/// continuation and its associated timeout task, cancelling the timeout
/// when a response arrives.
private class WalletContinuationTestHarness {
    /// Holds a pending request's continuation and timeout task.
    private struct PendingRequest {
        let continuation: CheckedContinuation<MockResult, any Error>
        let timeoutTask: Task<Void, Never>
    }

    /// Dictionary of pending requests keyed by request ID.
    private var pendingRequests: [NoteId: PendingRequest] = [:]

    /// Lock protecting access to `pendingRequests`.
    private let lock = NSLock()

    /// Result type returned by successful wallet operations.
    enum MockResult {
        case success
    }

    /// Errors that can occur while waiting for a wallet response.
    enum WaitError: Error {
        /// The request timed out before a response arrived.
        case timeout
    }

    /// Waits for a response to the given request ID.
    ///
    /// Registers a continuation that will be resumed when `resumeWithResult`
    /// or `resumeWithError` is called, or when the timeout expires.
    ///
    /// - Parameters:
    ///   - requestId: The unique identifier for this request.
    ///   - timeout: Maximum time to wait before throwing `WaitError.timeout`.
    /// - Returns: `MockResult.success` if resumed successfully.
    /// - Throws: `WaitError.timeout` if the timeout expires first.
    func waitForResponse(for requestId: NoteId, timeout: Duration = .seconds(10)) async throws -> MockResult {
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                self.resumeWithError(request: requestId, error: WaitError.timeout)
            }

            let pendingRequest = PendingRequest(continuation: continuation, timeoutTask: timeoutTask)

            lock.lock()
            pendingRequests[requestId] = pendingRequest
            lock.unlock()
        }
    }

    /// Resumes the continuation for the given request with a successful result.
    ///
    /// Cancels the associated timeout task and removes the pending request.
    /// If no pending request exists (already resumed or timed out), this is a no-op.
    ///
    /// - Parameter requestId: The request ID to resume.
    func resumeWithResult(request requestId: NoteId) {
        lock.lock()
        let pendingRequest = pendingRequests.removeValue(forKey: requestId)
        lock.unlock()

        pendingRequest?.timeoutTask.cancel()
        pendingRequest?.continuation.resume(returning: .success)
    }

    /// Resumes the continuation for the given request with an error.
    ///
    /// Cancels the associated timeout task and removes the pending request.
    /// If no pending request exists (already resumed), this is a no-op.
    ///
    /// - Parameters:
    ///   - requestId: The request ID to resume.
    ///   - error: The error to throw (defaults to `WaitError.timeout`).
    func resumeWithError(request requestId: NoteId, error: Error = WaitError.timeout) {
        lock.lock()
        let pendingRequest = pendingRequests.removeValue(forKey: requestId)
        lock.unlock()

        pendingRequest?.timeoutTask.cancel()
        pendingRequest?.continuation.resume(throwing: error)
    }
}
