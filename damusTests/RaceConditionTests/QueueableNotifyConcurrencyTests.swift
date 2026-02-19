//
//  QueueableNotifyConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: QueueableNotify continuation TOCTOU
//  Bead: damus-1kd
//

import XCTest
@testable import damus

final class QueueableNotifyConcurrencyTests: XCTestCase {

    // MARK: - Before fix: would be unsafe without actor isolation

    /// Reproduces master's QueueableNotify.add(item:) which had no actor isolation:
    ///   guard let continuation else { queue.append(item); return }  // GUARD
    ///   continuation.yield(item)                                     // USE
    /// Without actor isolation, two calls both pass guard before either yields,
    /// risking double-yield on a consumed continuation.
    func test_queueable_notify_toctou_before() {
        var continuation: String? = "active"
        let storageLock = NSLock()
        let bothPassedGuard = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Task 1: guard-then-use
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let hasContinuation = continuation != nil  // GUARD
            storageLock.unlock()
            barrier.arriveA()  // Both pass guard before either uses
            if hasContinuation {
                bothPassedGuard.increment()
                // Would call continuation.yield() here
            }
            group.leave()
        }

        // Task 2: also guard-then-use (re-entrant call)
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let hasContinuation = continuation != nil  // GUARD: also true
            storageLock.unlock()
            barrier.arriveB()
            if hasContinuation {
                bothPassedGuard.increment()
                // Would also call continuation.yield()
            }
            group.leave()
        }

        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "Threads should complete within timeout")
        XCTAssertEqual(bothPassedGuard.value, 2, "Master QueueableNotify bug: both tasks pass guard-let before either yields (continuation TOCTOU)")
    }

    // MARK: - After fix: actor isolation makes add(item:) safe

    /// QueueableNotify is an actor, so add(item:) is serialized.
    /// The guard let continuation + yield pattern cannot interleave.
    /// Items added before listening are queued, then delivered in order.
    func test_queueable_notify_toctou_after() async {
        let notify = QueueableNotify<Int>(maxQueueItems: 100)

        // Add items before anyone listens — they should be queued
        await notify.add(item: 1)
        await notify.add(item: 2)

        // Collect results in an actor for concurrency safety
        let collector = AtomicCounter()

        // Start listening — consumes queued items + one more
        let stream = await notify.stream
        let task = Task {
            var count = 0
            for await _ in stream {
                collector.increment()
                count += 1
                if count == 3 { break }
            }
        }

        // Yield to let the stream consumer start (cooperative scheduling)
        await Task.yield()
        await Task.yield()

        // Add one more while listening
        await notify.add(item: 3)

        await task.value

        XCTAssertEqual(collector.value, 3, "Actor serialization delivers all 3 items (2 queued + 1 live)")
    }
}
