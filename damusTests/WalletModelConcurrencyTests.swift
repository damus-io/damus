//
//  WalletModelConcurrencyTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-02.
//

import XCTest
import Dispatch
@testable import damus

/// Tests for WalletModel thread safety: verifies NSLock protects the
/// continuations dictionary from double-resume crashes.
final class WalletModelConcurrencyTests: XCTestCase {

    /// Races 10 concurrent resume calls on the same continuation.
    /// Without the NSLock fix, this crashes with double-resume SIGABRT.
    func testResume_ConcurrentCallsSameId_NoDoubleResume() async throws {
        for iteration in 0..<50 {
            let harness = WalletContinuationTestHarness()

            var bytes = [UInt8](repeating: 0, count: 32)
            bytes[0] = UInt8(iteration % 256)
            bytes[1] = UInt8(iteration / 256)
            let requestId = NoteId(Data(bytes))

            let expectation = XCTestExpectation(description: "Continuation resumed iteration \(iteration)")

            Task {
                do {
                    _ = try await harness.waitForResponse(for: requestId, timeout: .seconds(5))
                } catch {
                    // Timeout acceptable in race test
                }
                expectation.fulfill()
            }

            try await Task.sleep(for: .milliseconds(10))

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

    /// 30 concurrent waitForResponse calls with unique IDs, all resumed concurrently.
    func testWaitForResponse_ManyConcurrentRequests_AllComplete() async throws {
        let harness = WalletContinuationTestHarness()

        let concurrentRequests = 30
        let expectation = XCTestExpectation(description: "All requests complete")
        expectation.expectedFulfillmentCount = concurrentRequests

        var requestIds: [NoteId] = []
        let requestIdsLock = NSLock()

        for i in 0..<concurrentRequests {
            Task {
                var bytes = [UInt8](repeating: 0, count: 32)
                bytes[0] = UInt8(i % 256)
                bytes[1] = UInt8(i / 256)
                let requestId = NoteId(Data(bytes))

                requestIdsLock.lock()
                requestIds.append(requestId)
                requestIdsLock.unlock()

                do {
                    _ = try await harness.waitForResponse(for: requestId, timeout: .seconds(5))
                } catch {
                    XCTFail("Request \(i) failed unexpectedly: \(error)")
                }
                expectation.fulfill()
            }
        }

        try await Task.sleep(for: .milliseconds(100))

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

    /// Stress test: 20 iterations of 10 concurrent requests.
    func testContinuations_StressTest_ManyIterations() async throws {
        for iteration in 0..<20 {
            let harness = WalletContinuationTestHarness()
            let requestsPerIteration = 10
            let expectation = XCTestExpectation(description: "Iteration \(iteration)")
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
                    } catch {
                        // Timeout acceptable in stress test
                    }
                    expectation.fulfill()
                }
            }

            try await Task.sleep(for: .milliseconds(Int.random(in: 1...30)))

            for requestId in requestIds.shuffled() {
                harness.resumeWithResult(request: requestId)
            }

            await fulfillment(of: [expectation], timeout: 5.0)
        }
    }

    /// Verifies timeout cleans up the continuation (late resume is a no-op).
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
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        // Late resume should be a no-op, not crash
        harness.resumeWithResult(request: requestId)
    }
}

// MARK: - Test Harness

/// Isolates the NSLock + continuation pattern from WalletModel for testing.
private class WalletContinuationTestHarness {
    private struct PendingRequest {
        let continuation: CheckedContinuation<MockResult, any Error>
        let timeoutTask: Task<Void, Never>
    }

    private var pendingRequests: [NoteId: PendingRequest] = [:]
    private let lock = NSLock()

    enum MockResult { case success }
    enum WaitError: Error { case timeout }

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

    func resumeWithResult(request requestId: NoteId) {
        lock.lock()
        let pendingRequest = pendingRequests.removeValue(forKey: requestId)
        lock.unlock()

        pendingRequest?.timeoutTask.cancel()
        pendingRequest?.continuation.resume(returning: .success)
    }

    func resumeWithError(request requestId: NoteId, error: Error = WaitError.timeout) {
        lock.lock()
        let pendingRequest = pendingRequests.removeValue(forKey: requestId)
        lock.unlock()

        pendingRequest?.timeoutTask.cancel()
        pendingRequest?.continuation.resume(throwing: error)
    }
}
