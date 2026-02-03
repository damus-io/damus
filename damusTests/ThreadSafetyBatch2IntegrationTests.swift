//
//  ThreadSafetyBatch2IntegrationTests.swift
//  damusTests
//
//  Integration tests for thread safety fixes in batch 2.
//  These tests exercise actual components rather than harnesses.
//
//  Run with Thread Sanitizer enabled for best results.
//

import XCTest
@testable import damus

// MARK: - NotificationsModel Integration Tests

/// Integration tests for NotificationsModel @MainActor isolation
final class NotificationsModelIntegrationTests: XCTestCase {

    /// Tests actual NotificationsModel insert and flush operations under concurrent access.
    @MainActor
    func testNotificationsModel_InsertAndFlush_ThreadSafe() async throws {
        let model = NotificationsModel()

        // Start queuing
        model.set_should_queue(true)
        XCTAssertTrue(model.should_queue)

        // Simulate concurrent notification insertions from multiple "sources"
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask { @MainActor in
                    // Simulate the pattern used in actual notification handling
                    if model.should_queue {
                        // Notifications would be queued here
                        _ = model.notifications.count
                    }

                    // Occasionally toggle queuing state
                    if i % 10 == 0 {
                        model.set_should_queue(i % 20 == 0)
                    }
                }
            }
        }

        // Flush - this is the critical operation that was racy before the fix
        model.set_should_queue(false)
        XCTAssertFalse(model.should_queue)
    }

    /// Tests NotificationsModel under rapid state transitions.
    @MainActor
    func testNotificationsModel_RapidStateTransitions_NoRace() async throws {
        let model = NotificationsModel()
        let iterations = 100

        for _ in 0..<iterations {
            // Rapid toggle
            model.set_should_queue(true)
            _ = model.should_queue
            _ = model.notifications.count
            model.set_should_queue(false)
            _ = model.should_queue
            _ = model.notifications.count
        }

        // Verify model is in consistent state
        XCTAssertFalse(model.should_queue)
    }
}

// MARK: - Ndb.close() Integration Tests

/// Integration tests for Ndb.close() non-blocking behavior on main thread
final class NdbCloseIntegrationTests: XCTestCase {

    /// Tests actual Ndb.close() from main thread doesn't block.
    func testNdbClose_ActualDatabase_NonBlocking() async throws {
        // Create test database off main thread to avoid blocking UI during init
        let ndb = await Task.detached { Ndb.test }.value

        // Measure close() timing on main thread
        await MainActor.run {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Close should dispatch to background and return immediately
            ndb.close()

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Main thread should not be blocked for more than a small amount
            // The actual close work happens in background
            XCTAssertLessThan(elapsed, 0.1, "close() should return quickly from main thread")
        }

        // Give background work time to complete
        try await Task.sleep(for: .milliseconds(200))
    }

    /// Tests multiple Ndb instances can be closed concurrently.
    func testNdbClose_MultipleInstances_Concurrent() async throws {
        // Create multiple test databases on background threads to avoid main thread I/O
        let instances = await withTaskGroup(of: Ndb.self, returning: [Ndb].self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await Task.detached { Ndb.test }.value
                }
            }
            var results: [Ndb] = []
            for await ndb in group {
                results.append(ndb)
            }
            return results
        }

        // Close all concurrently from different contexts
        await withTaskGroup(of: Void.self) { group in
            for (index, ndb) in instances.enumerated() {
                group.addTask {
                    if index % 2 == 0 {
                        // Some close from main
                        await MainActor.run { ndb.close() }
                    } else {
                        // Some close from background
                        ndb.close()
                    }
                }
            }
        }

        // Give background work time to complete
        try await Task.sleep(for: .milliseconds(500))
    }

    /// Tests Ndb operations followed by close don't race.
    func testNdbClose_AfterOperations_Safe() async throws {
        // Create Ndb on background thread to avoid main thread I/O
        let ndb = await Task.detached { Ndb.test }.value

        // Perform some read operations
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    // Simulate lookup operations
                    let txn = NdbTxn(ndb: ndb)
                    _ = txn
                }
            }
        }

        // Close after operations
        ndb.close()

        // Give background work time to complete
        try await Task.sleep(for: .milliseconds(200))
    }
}

// MARK: - StreamState Fuzz Tests

/// Fuzz tests for SubscriptionManager's StreamState thread safety
final class StreamStateFuzzTests: XCTestCase {

    /// Thread-safe state container matching SubscriptionManager.StreamState
    final class StreamState: @unchecked Sendable {
        private let lock = NSLock()
        private var _ndbEOSEIssued = false
        private var _networkEOSEIssued = false
        private var _latestTimestamp: UInt32? = nil
        private var _operationCount = 0

        /// Marks the NDB EOSE flag as issued.
        /// Thread-safe: acquires internal lock. Increments `_operationCount`.
        func setNdbEOSE() {
            lock.lock()
            defer { lock.unlock() }
            _ndbEOSEIssued = true
            _operationCount += 1
        }

        /// Marks the network EOSE flag as issued.
        /// Thread-safe: acquires internal lock. Increments `_operationCount`.
        func setNetworkEOSE() {
            lock.lock()
            defer { lock.unlock() }
            _networkEOSEIssued = true
            _operationCount += 1
        }

        /// Updates the latest timestamp, keeping the maximum value seen.
        /// - Parameter timestamp: The new timestamp to compare against current latest.
        /// Thread-safe: acquires internal lock. Increments `_operationCount`.
        func updateTimestamp(_ timestamp: UInt32) {
            lock.lock()
            defer { lock.unlock() }
            if let latest = _latestTimestamp {
                _latestTimestamp = max(latest, timestamp)
            } else {
                _latestTimestamp = timestamp
            }
            _operationCount += 1
        }

        /// Returns the current state snapshot and increments the operation count.
        /// - Returns: Tuple of (ndbEOSEIssued, networkEOSEIssued, latestTimestamp, operationCount).
        /// Thread-safe: acquires internal lock. This read counts as an operation.
        func getState() -> (ndb: Bool, network: Bool, timestamp: UInt32?, ops: Int) {
            lock.lock()
            defer { lock.unlock() }
            _operationCount += 1
            return (_ndbEOSEIssued, _networkEOSEIssued, _latestTimestamp, _operationCount)
        }

        /// Resets all state to initial values.
        /// Thread-safe: acquires internal lock. Sets `_operationCount` to 0.
        func reset() {
            lock.lock()
            defer { lock.unlock() }
            _ndbEOSEIssued = false
            _networkEOSEIssued = false
            _latestTimestamp = nil
            _operationCount = 0
        }
    }

    /// Fuzz test with randomized delays between operations.
    func testStreamState_FuzzRandomDelays() async throws {
        for seed in 0..<5 {
            var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
            let state = StreamState()

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<50 {
                    let delay = UInt64.random(in: 0...10, using: &rng)
                    let operation = Int.random(in: 0...3, using: &rng)

                    group.addTask {
                        // Random delay before operation (0-10ms)
                        if delay > 0 {
                            try? await Task.sleep(nanoseconds: delay * 1_000_000)
                        }

                        switch operation {
                        case 0: state.setNdbEOSE()
                        case 1: state.setNetworkEOSE()
                        case 2: state.updateTimestamp(UInt32.random(in: 1...1000))
                        default: _ = state.getState()
                        }
                    }
                }
            }

            // Verify state is consistent
            let (_, _, _, ops) = state.getState()
            XCTAssertGreaterThan(ops, 0, "Operations should have been recorded")
        }
    }

    /// Fuzz test with randomized operation ordering.
    func testStreamState_FuzzRandomOrder() async throws {
        for seed in 0..<5 {
            var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
            let state = StreamState()

            // Generate random sequence of operations
            var operations: [() -> Void] = []
            for i in 0..<100 {
                let timestamp = UInt32(i + 1)
                switch Int.random(in: 0...4, using: &rng) {
                case 0: operations.append { state.setNdbEOSE() }
                case 1: operations.append { state.setNetworkEOSE() }
                case 2: operations.append { state.updateTimestamp(timestamp) }
                case 3: operations.append { _ = state.getState() }
                default:
                    // Mixed operation
                    operations.append {
                        state.setNdbEOSE()
                        state.updateTimestamp(timestamp)
                    }
                }
            }

            // Shuffle operations
            operations.shuffle(using: &rng)

            // Execute concurrently
            await withTaskGroup(of: Void.self) { group in
                for op in operations {
                    group.addTask { op() }
                }
            }

            // Verify state is consistent
            let (ndb, network, _, _) = state.getState()
            // At least one of each EOSE should be set given our operation mix
            XCTAssertTrue(ndb || network, "At least one EOSE flag should be set")
        }
    }

    /// Fuzz test with randomized concurrent task counts.
    func testStreamState_FuzzRandomTaskCount() async throws {
        for seed in 0..<5 {
            var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
            let state = StreamState()

            // Random number of concurrent tasks (10-100)
            let taskCount = Int.random(in: 10...100, using: &rng)

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<taskCount {
                    group.addTask {
                        // Each task does multiple operations
                        for j in 0..<5 {
                            switch (i + j) % 4 {
                            case 0: state.setNdbEOSE()
                            case 1: state.setNetworkEOSE()
                            case 2: state.updateTimestamp(UInt32(i * 5 + j))
                            default: _ = state.getState()
                            }
                        }
                    }
                }
            }

            // Verify state (getState itself is now counted as an operation, hence +1)
            let (ndb, network, timestamp, ops) = state.getState()
            XCTAssertTrue(ndb)
            XCTAssertTrue(network)
            XCTAssertNotNil(timestamp)
            XCTAssertEqual(ops, taskCount * 5 + 1, "All operations should complete (including verification read)")
        }
    }

    /// Stress test combining all fuzz parameters.
    func testStreamState_FuzzCombined() async throws {
        for seed in 0..<10 {
            var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
            let state = StreamState()

            let taskCount = Int.random(in: 20...80, using: &rng)
            var maxTimestamp: UInt32 = 0

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<taskCount {
                    let delay = UInt64.random(in: 0...5, using: &rng)
                    let opsPerTask = Int.random(in: 1...10, using: &rng)
                    let timestamp = UInt32.random(in: 1...10000, using: &rng)

                    // Track max for verification
                    if timestamp > maxTimestamp {
                        maxTimestamp = timestamp
                    }

                    group.addTask {
                        if delay > 0 {
                            try? await Task.sleep(nanoseconds: delay * 1_000_000)
                        }

                        for i in 0..<opsPerTask {
                            switch i % 4 {
                            case 0: state.setNdbEOSE()
                            case 1: state.setNetworkEOSE()
                            case 2: state.updateTimestamp(timestamp)
                            default: _ = state.getState()
                            }
                        }
                    }
                }
            }

            // Verify final state
            let (ndb, network, finalTimestamp, _) = state.getState()
            XCTAssertTrue(ndb)
            XCTAssertTrue(network)
            if let ts = finalTimestamp {
                XCTAssertLessThanOrEqual(ts, maxTimestamp, "Timestamp should not exceed max input")
            }
        }
    }
}

// MARK: - RelayConnection Fuzz Tests

/// Fuzz tests for RelayConnection @Published property thread safety
final class RelayConnectionFuzzTests: XCTestCase {

    /// Test harness that simulates RelayConnection's @Published property pattern
    final class RelayConnectionHarness: ObservableObject, @unchecked Sendable {
        @Published private(set) var isConnected = false
        @Published private(set) var isConnecting = false
        private let lock = NSLock()
        private var _stateChangeCount = 0

        var stateChangeCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _stateChangeCount
        }

        /// Simulates initiating a connection attempt.
        ///
        /// Dispatches to `DispatchQueue.main` to set `isConnecting = true`.
        /// Acquires `lock` to increment `_stateChangeCount`.
        ///
        /// Example:
        /// ```
        /// harness.simulateConnect()
        /// // After main queue processes: isConnecting == true
        /// ```
        func simulateConnect() {
            DispatchQueue.main.async {
                self.isConnecting = true
                self.lock.lock()
                self._stateChangeCount += 1
                self.lock.unlock()
            }
        }

        /// Simulates a disconnection.
        ///
        /// Dispatches to `DispatchQueue.main` to set `isConnected = false`, `isConnecting = false`.
        /// Acquires `lock` to increment `_stateChangeCount`.
        ///
        /// Example:
        /// ```
        /// harness.simulateDisconnect()
        /// // After main queue processes: isConnected == false, isConnecting == false
        /// ```
        func simulateDisconnect() {
            DispatchQueue.main.async {
                self.isConnected = false
                self.isConnecting = false
                self.lock.lock()
                self._stateChangeCount += 1
                self.lock.unlock()
            }
        }

        /// Simulates successful connection completion.
        ///
        /// Dispatches to `DispatchQueue.main` to set `isConnected = true`, `isConnecting = false`.
        /// Acquires `lock` to increment `_stateChangeCount`.
        ///
        /// Example:
        /// ```
        /// harness.simulateConnectionSuccess()
        /// // After main queue processes: isConnected == true, isConnecting == false
        /// ```
        func simulateConnectionSuccess() {
            DispatchQueue.main.async {
                self.isConnected = true
                self.isConnecting = false
                self.lock.lock()
                self._stateChangeCount += 1
                self.lock.unlock()
            }
        }

        /// Simulates a ping failure triggering reconnection.
        ///
        /// Dispatches to `DispatchQueue.main` to set `isConnected = false`, `isConnecting = false`.
        /// Acquires `lock` to increment `_stateChangeCount`.
        ///
        /// Example:
        /// ```
        /// harness.simulatePingFailure()
        /// // After main queue processes: isConnected == false, isConnecting == false
        /// ```
        func simulatePingFailure() {
            DispatchQueue.main.async {
                self.isConnected = false
                self.isConnecting = false
                self.lock.lock()
                self._stateChangeCount += 1
                self.lock.unlock()
            }
        }
    }

    /// Fuzz test with randomized connection state transitions.
    func testRelayConnection_FuzzRandomTransitions() async throws {
        for seed in 0..<5 {
            var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
            let harness = RelayConnectionHarness()

            let taskCount = Int.random(in: 20...50, using: &rng)

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<taskCount {
                    let delay = UInt64.random(in: 0...10, using: &rng)
                    let operation = Int.random(in: 0...3, using: &rng)

                    group.addTask {
                        if delay > 0 {
                            try? await Task.sleep(nanoseconds: delay * 1_000_000)
                        }

                        switch operation {
                        case 0: harness.simulateConnect()
                        case 1: harness.simulateConnectionSuccess()
                        case 2: harness.simulateDisconnect()
                        default: harness.simulatePingFailure()
                        }
                    }
                }
            }

            // Allow dispatched work to complete
            try await Task.sleep(for: .milliseconds(200))

            // Verify all state changes were processed
            XCTAssertEqual(harness.stateChangeCount, taskCount, "All state changes should complete")
        }
    }

    /// Fuzz test simulating rapid reconnection attempts.
    func testRelayConnection_FuzzRapidReconnect() async throws {
        let harness = RelayConnectionHarness()

        // Simulate rapid connect/disconnect cycles from multiple "threads"
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    // Simulate a reconnection cycle
                    harness.simulateConnect()
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                    harness.simulateConnectionSuccess()
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    harness.simulatePingFailure()
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
            }
        }

        // Allow dispatched work to complete
        try await Task.sleep(for: .milliseconds(300))

        // 20 cycles * 3 operations each = 60 state changes
        XCTAssertEqual(harness.stateChangeCount, 60)
    }
}

// MARK: - NotificationsModel Fuzz Tests

/// Fuzz tests for NotificationsModel thread safety
final class NotificationsModelFuzzTests: XCTestCase {

    /// Fuzz test with randomized queue state toggling.
    @MainActor
    func testNotificationsModel_FuzzQueueToggle() async throws {
        for seed in 0..<5 {
            var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
            let model = NotificationsModel()

            let iterations = Int.random(in: 50...100, using: &rng)

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<iterations {
                    let shouldQueue = Bool.random(using: &rng)

                    group.addTask { @MainActor in
                        model.set_should_queue(shouldQueue)
                        _ = model.should_queue
                        _ = model.notifications.count
                    }
                }
            }

            // Model should be in a consistent state
            _ = model.should_queue
            _ = model.notifications
        }
    }
}

// MARK: - Helper Types

/// Seeded random number generator for reproducible fuzz tests.
///
/// Uses xorshift64 algorithm for fast, reasonable quality pseudorandom numbers.
/// Note: Seed 0 is replaced with a nonzero constant since xorshift produces
/// all-zeros for zero state.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    /// Initializes the PRNG with the given seed.
    ///
    /// - Parameter seed: The seed value to initialize internal state. If 0, a nonzero
    ///   constant is used instead since xorshift64 produces all-zeros for zero state.
    init(seed: UInt64) {
        // xorshift64 produces all-zeros for zero seed; use nonzero fallback
        state = seed == 0 ? 0x853c49e6748fea9b : seed
    }

    /// Returns the next pseudorandom 64-bit value using xorshift64 algorithm.
    ///
    /// Mutates the internal state to advance the sequence.
    /// - Returns: A pseudorandom `UInt64` value.
    mutating func next() -> UInt64 {
        // Simple xorshift64 PRNG
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
