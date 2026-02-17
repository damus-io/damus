//
//  RaceConditionTestHelpers.swift
//  damusTests
//
//  Test infrastructure for deterministic race condition testing.
//

import Foundation
import os
import XCTest

// MARK: - ConcurrentBarrier

/// Two semaphores that force exact A→B→A interleaving at a race point.
///
/// Usage:
/// ```
/// let barrier = ConcurrentBarrier()
///
/// // Thread A
/// barrier.arriveA()  // signals A is ready, blocks until B arrives
/// // ... A continues after B has arrived ...
///
/// // Thread B
/// barrier.arriveB()  // blocks until A is ready, then signals A to continue
/// // ... B continues after unblocking A ...
/// ```
struct ConcurrentBarrier {
    private let semA = DispatchSemaphore(value: 0)
    private let semB = DispatchSemaphore(value: 0)

    /// Called by thread A: signals readiness, then waits for B to arrive.
    func arriveA() {
        semA.signal()   // tell B that A is ready
        semB.wait()     // wait for B to arrive
    }

    /// Called by thread B: waits for A to be ready, then signals own arrival.
    func arriveB() {
        semA.wait()     // wait for A to be ready
        semB.signal()   // tell A that B has arrived
    }
}

// MARK: - AtomicCounter

/// Thread-safe counter using OSAllocatedUnfairLock (heap-allocated, safe with classes).
final class AtomicCounter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Int32(0))

    var value: Int32 {
        lock.withLock { $0 }
    }

    @discardableResult
    func increment() -> Int32 {
        lock.withLock { state in
            state += 1
            return state
        }
    }

    func reset() {
        lock.withLock { $0 = 0 }
    }
}

// MARK: - ResumeTracker

/// Counts continuation resume calls without actually resuming a real continuation.
/// This avoids the fatal crash from double-resuming `CheckedContinuation`.
///
/// - `UnsafeResumeTracker`: plain dictionary, no lock — used in `_before` tests
/// - `SafeResumeTracker`: NSLock-protected — used in `_after` tests
class UnsafeResumeTracker {
    var continuations: [String: Bool] = [:]  // id -> has been resumed
    let counter = AtomicCounter()

    func store(_ id: String) {
        continuations[id] = false
    }

    /// Returns true if this call actually "resumed" (i.e. the continuation hadn't been consumed yet)
    @discardableResult
    func resume(_ id: String) -> Bool {
        guard let alreadyResumed = continuations[id], !alreadyResumed else {
            return false
        }
        continuations[id] = true
        counter.increment()
        return true
    }
}

/// NSLock-protected resume tracker — used in `_after` tests to verify
/// that the fix prevents double-resume on the same continuation ID.
class SafeResumeTracker {
    private var continuations: [String: Bool] = [:]
    private let lock = NSLock()
    let counter = AtomicCounter()

    func store(_ id: String) {
        lock.lock()
        continuations[id] = false
        lock.unlock()
    }

    @discardableResult
    func resume(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let alreadyResumed = continuations[id], !alreadyResumed else {
            return false
        }
        continuations[id] = true
        counter.increment()
        return true
    }
}

// MARK: - concurrentStress

/// Launches `workers` × `iterations` concurrent operations and waits for all to complete.
///
/// Returns the number of operations that completed successfully (reported via the `report` closure).
///
/// - Parameters:
///   - workers: Number of concurrent tasks
///   - iterations: Number of iterations per worker
///   - operation: The work to perform. Call `report()` once per successful mutation.
/// - Returns: Total count of reported successes
func concurrentStress(
    workers: Int,
    iterations: Int,
    operation: @escaping (_ workerId: Int, _ iteration: Int, _ report: @escaping () -> Void) -> Void
) -> Int {
    let counter = AtomicCounter()
    let group = DispatchGroup()

    for w in 0..<workers {
        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                operation(w, i) {
                    counter.increment()
                }
                group.leave()
            }
        }
    }

    group.wait()
    return Int(counter.value)
}

/// Async version of concurrentStress for @MainActor-isolated code.
/// Launches concurrent tasks and waits for all to complete.
func concurrentStressAsync(
    workers: Int,
    iterations: Int,
    operation: @escaping @Sendable (_ workerId: Int, _ iteration: Int) async -> Bool
) async -> Int {
    let counter = AtomicCounter()

    await withTaskGroup(of: Void.self) { group in
        for w in 0..<workers {
            for i in 0..<iterations {
                group.addTask {
                    let success = await operation(w, i)
                    if success {
                        counter.increment()
                    }
                }
            }
        }
    }

    return Int(counter.value)
}

// MARK: - assertEventually

/// Polls a condition up to `timeout` seconds, failing the test if it never becomes true.
func assertEventually(
    timeout: TimeInterval = 2.0,
    interval: TimeInterval = 0.01,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ message: @autoclosure () -> String = "Condition was never met",
    condition: () -> Bool
) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        Thread.sleep(forTimeInterval: interval)
    }
    XCTFail(message(), file: file, line: line)
}
