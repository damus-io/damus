//
//  NostrNetworkManagerConcurrencyTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-02.
//

import XCTest
import Dispatch
@testable import damus

/// Tests for NostrNetworkManager thread safety: verifies NSLock protects
/// the continuations dictionary from double-resume crashes.
final class NostrNetworkManagerConcurrencyTests: XCTestCase {

    /// 50 concurrent awaitConnection() calls, all resumed by connect().
    /// Without the atomic removeValue fix, this crashes with double-resume.
    func testAwaitConnection_ConcurrentCalls_NoDoubleResume() async throws {
        let harness = ConnectionContinuationTestHarness()

        let concurrentCallers = 50
        let expectation = XCTestExpectation(description: "All callers complete")
        expectation.expectedFulfillmentCount = concurrentCallers

        for _ in 0..<concurrentCallers {
            Task {
                await harness.awaitConnection(timeout: .seconds(5))
                expectation.fulfill()
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        await harness.connect()

        await fulfillment(of: [expectation], timeout: 10.0)
    }

    /// Races timeout against connect() with very short timeout windows.
    func testAwaitConnection_TimeoutRacesWithConnect_NoDoubleResume() async throws {
        for _ in 0..<20 {
            let harness = ConnectionContinuationTestHarness()
            let expectation = XCTestExpectation(description: "Caller completes")

            Task {
                await harness.awaitConnection(timeout: .milliseconds(10))
                expectation.fulfill()
            }

            Task {
                await harness.connect()
            }

            await fulfillment(of: [expectation], timeout: 2.0)
        }
    }

    /// Stress test: 10 iterations of 20 concurrent callers.
    func testAwaitConnection_StressTest_ManyIterations() async throws {
        for iteration in 0..<10 {
            let harness = ConnectionContinuationTestHarness()
            let concurrentCallersPerIteration = 20
            let expectation = XCTestExpectation(description: "Iteration \(iteration)")
            expectation.expectedFulfillmentCount = concurrentCallersPerIteration

            for _ in 0..<concurrentCallersPerIteration {
                Task {
                    await harness.awaitConnection(timeout: .seconds(2))
                    expectation.fulfill()
                }
            }

            try await Task.sleep(for: .milliseconds(Int.random(in: 1...50)))
            await harness.connect()

            await fulfillment(of: [expectation], timeout: 5.0)
        }
    }

    /// Already-connected callers should return immediately without blocking.
    func testAwaitConnection_AlreadyConnected_ImmediateReturn() async throws {
        let harness = ConnectionContinuationTestHarness()
        await harness.connect()

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
        XCTAssertLessThan(elapsed, 1.0, "Already-connected calls should return immediately")
    }
}

// MARK: - Test Harness

/// Isolates the NSLock + continuation pattern from NostrNetworkManager for testing.
private final class ConnectionContinuationTestHarness: @unchecked Sendable {
    private var isConnected = false
    private var connectionContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]
    private let continuationsLock = NSLock()

    func awaitConnection(timeout: Duration = .seconds(30)) async {
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

    func resumeConnectionContinuation(requestId: UUID) {
        continuationsLock.lock()
        let continuation = connectionContinuations.removeValue(forKey: requestId)
        continuationsLock.unlock()

        continuation?.resume()
    }

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
}
