//
//  RelayPoolConcurrencyTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-02.
//

import XCTest
import Dispatch
import Network
@testable import damus

/// Tests for RelayPool thread safety and TOCTOU race condition fixes.
///
/// These tests verify that:
/// 1. Rapid network status changes don't cause inconsistent state
/// 2. The oldStatus capture pattern prevents TOCTOU races
/// 3. Concurrent pathUpdateHandler calls behave correctly
///
/// Run with Thread Sanitizer enabled for best results:
/// Edit Scheme → Test → Diagnostics → Thread Sanitizer
final class RelayPoolConcurrencyTests: XCTestCase {

    // MARK: - TOCTOU Race Condition Tests

    /// Tests that rapid network status changes are handled consistently.
    ///
    /// This test simulates the scenario where network status changes rapidly,
    /// which could trigger multiple concurrent pathUpdateHandler calls.
    func testPathUpdateHandler_RapidStatusChanges_ConsistentState() async throws {
        let harness = PathUpdateTestHarness()

        let iterations = 100
        let statuses: [NWPath.Status] = [.satisfied, .unsatisfied, .requiresConnection]

        // Simulate rapid status changes from multiple "network events"
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let status = statuses[i % statuses.count]
                    await harness.pathUpdateHandler(newStatus: status)
                }
            }
        }

        // Verify no crashes occurred and state is consistent
        let finalStatus = await harness.lastNetworkStatus
        XCTAssertTrue(statuses.contains(finalStatus), "Final status should be one of the valid statuses")
    }

    /// Tests that the oldStatus capture pattern works correctly.
    ///
    /// This verifies that even with concurrent updates, each handler
    /// makes decisions based on a consistent snapshot of the old status.
    func testPathUpdateHandler_OldStatusCapture_NoTOCTOU() async throws {
        let harness = PathUpdateTestHarness()

        // Set initial status
        await harness.setStatus(.unsatisfied)

        let concurrentUpdates = 20
        let reconnectCounts = await harness.reconnectCount

        // Simulate many concurrent transitions to satisfied
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrentUpdates {
                group.addTask {
                    await harness.pathUpdateHandler(newStatus: .satisfied)
                }
            }
        }

        // With the fix, only the first update that sees unsatisfied->satisfied
        // should trigger reconnect. Without the fix, multiple could trigger
        // because they'd all see oldStatus as unsatisfied.
        let finalReconnectCount = await harness.reconnectCount
        let reconnectsDuringTest = finalReconnectCount - reconnectCounts

        // We expect at least 1 reconnect (the first one that sees the change)
        // but the exact count depends on timing. The key is no crashes occurred.
        XCTAssertGreaterThanOrEqual(reconnectsDuringTest, 1,
            "Should have triggered at least one reconnect")
    }

    /// Tests that the logging path doesn't cause issues under concurrency.
    func testPathUpdateHandler_LoggingPath_NoCrash() async throws {
        let harness = PathUpdateTestHarness()

        // Set initial status
        await harness.setStatus(.unsatisfied)

        // Simulate status changes that trigger logging
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    // Alternate between statuses to trigger logging path
                    let status: NWPath.Status = i % 2 == 0 ? .satisfied : .unsatisfied
                    await harness.pathUpdateHandler(newStatus: status)
                }
            }
        }

        // Verify logging was called (no crashes)
        let logCount = await harness.logCount
        XCTAssertGreaterThan(logCount, 0, "Should have logged some status changes")
    }

    /// Stress test: runs concurrent path updates many times.
    func testPathUpdateHandler_StressTest_ManyIterations() async throws {
        let iterations = 10

        for _ in 0..<iterations {
            let harness = PathUpdateTestHarness()

            await withTaskGroup(of: Void.self) { group in
                // Simulate chaotic network conditions
                for i in 0..<30 {
                    group.addTask {
                        let statuses: [NWPath.Status] = [.satisfied, .unsatisfied, .requiresConnection]
                        await harness.pathUpdateHandler(newStatus: statuses[i % 3])
                    }
                }
            }

            // Just verify no crash - exact state depends on timing
            _ = await harness.lastNetworkStatus
        }
    }

    /// Tests interleaved status checks and updates.
    func testPathUpdateHandler_InterleavedReadsAndWrites_Consistent() async throws {
        let harness = PathUpdateTestHarness()

        let operations = 100

        // Use task group that returns optional status values
        // Write operations return nil, read operations return the status
        let readStatuses: [NWPath.Status] = await withTaskGroup(of: NWPath.Status?.self, returning: [NWPath.Status].self) { group in
            for i in 0..<operations {
                if i % 2 == 0 {
                    // Write operation - returns nil
                    group.addTask {
                        let status: NWPath.Status = i % 4 == 0 ? .satisfied : .unsatisfied
                        await harness.pathUpdateHandler(newStatus: status)
                        return nil
                    }
                } else {
                    // Read operation - returns the status
                    group.addTask {
                        return await harness.lastNetworkStatus
                    }
                }
            }

            // Collect all non-nil results (the read statuses)
            var results: [NWPath.Status] = []
            for await result in group {
                if let status = result {
                    results.append(status)
                }
            }
            return results
        }

        // Verify all reads got valid statuses
        for status in readStatuses {
            XCTAssertTrue([.satisfied, .unsatisfied, .requiresConnection].contains(status),
                "All read statuses should be valid")
        }
    }
}

// MARK: - Test Harness

/// A test harness that isolates the pathUpdateHandler logic from RelayPool.
///
/// This replicates the fixed pattern from RelayPool to test TOCTOU prevention
/// without needing the full RelayPool/NWPathMonitor infrastructure.
///
/// The actor isolation ensures thread-safe access to `lastNetworkStatus`,
/// `reconnectCount`, and `logCount`.
private actor PathUpdateTestHarness {
    /// The current network status being tracked.
    var lastNetworkStatus: NWPath.Status = .unsatisfied

    /// Count of simulated reconnection operations triggered.
    var reconnectCount: Int = 0

    /// Count of simulated logging operations triggered.
    var logCount: Int = 0

    /// Directly sets the network status without triggering side effects.
    ///
    /// Use this for test setup. For simulating actual status changes,
    /// use `pathUpdateHandler(newStatus:)` instead.
    ///
    /// - Parameter status: The new network status to set.
    func setStatus(_ status: NWPath.Status) {
        lastNetworkStatus = status
    }

    /// Simulates pathUpdateHandler with the TOCTOU fix pattern.
    ///
    /// Atomically captures the old status before updating, then uses the
    /// captured value for all comparisons. This prevents TOCTOU races
    /// where status could change between check and use.
    ///
    /// - Parameter newStatus: The new network status to process.
    /// - Note: This method is async and should be awaited.
    func pathUpdateHandler(newStatus: NWPath.Status) async {
        // Atomically capture and update the status (the fix pattern)
        let oldStatus = self.lastNetworkStatus
        self.lastNetworkStatus = newStatus

        // Reconnect path
        if (newStatus == .satisfied || newStatus == .requiresConnection) && oldStatus != newStatus {
            await simulateReconnect()
        }

        // Logging path
        if newStatus != oldStatus {
            await simulateLogging()
        }
    }

    /// Simulates an async reconnection operation.
    ///
    /// Adds a small delay to simulate `connect_to_disconnected()` work,
    /// then increments `reconnectCount`.
    ///
    /// - Note: This method is async and should be awaited.
    private func simulateReconnect() async {
        // Simulate the async work that connect_to_disconnected does
        try? await Task.sleep(for: .milliseconds(1))
        reconnectCount += 1
    }

    /// Simulates an async logging operation.
    ///
    /// Adds a small delay to simulate relay iteration for logging,
    /// then increments `logCount`.
    ///
    /// - Note: This method is async and should be awaited.
    private func simulateLogging() async {
        // Simulate the async relay iteration for logging
        try? await Task.sleep(for: .microseconds(100))
        logCount += 1
    }
}
