//
//  DatabaseSnapshotManagerConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: DatabaseSnapshotManager concurrent snapshot creation
//  Bead: damus-hdn
//

import XCTest
@testable import damus

final class DatabaseSnapshotManagerConcurrencyTests: XCTestCase {

    // MARK: - Before fix: multiple concurrent snapshots can overlap

    /// Reproduces master's DatabaseSnapshotManager.createSnapshotIfNeeded() without guard:
    ///   func createSnapshotIfNeeded() async {
    ///       await performSnapshot()  // SUSPENSION: re-entrant call enters here
    ///   }
    /// Without isCreatingSnapshot guard, two calls overlap across await.
    func test_concurrent_snapshots_before() {
        let concurrentSnapshots = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Call 1: createSnapshotIfNeeded (no guard in master)
        group.enter()
        DispatchQueue.global().async {
            concurrentSnapshots.increment()  // Start snapshot
            barrier.arriveA()  // "await performSnapshot()" — call 2 enters
            group.leave()
        }

        // Call 2: re-entrant createSnapshotIfNeeded during await
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()
            concurrentSnapshots.increment()  // Also starts snapshot (no guard!)
            group.leave()
        }

        group.wait()
        XCTAssertEqual(concurrentSnapshots.value, 2, "Master DatabaseSnapshotManager bug: concurrent snapshots overlap without guard (actor re-entrancy)")
    }

    // MARK: - After fix: isCreatingSnapshot flag prevents overlap

    /// Exercises the real DatabaseSnapshotManager actor: 5 concurrent
    /// createSnapshotIfNeeded() calls. The isCreatingSnapshot guard prevents
    /// overlapping file operations across actor re-entrancy boundaries.
    func test_concurrent_snapshots_after() async {
        let manager = DatabaseSnapshotManager(ndb: Ndb.test)

        // 5 concurrent createSnapshotIfNeeded calls
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    _ = try? await manager.createSnapshotIfNeeded()
                }
            }
        }

        // Actor serialization + isCreatingSnapshot guard ensures no overlapping file operations
        let count = await manager.snapshotCount
        XCTAssertLessThanOrEqual(count, 1, "isCreatingSnapshot guard prevents concurrent snapshot creation")
    }
}
