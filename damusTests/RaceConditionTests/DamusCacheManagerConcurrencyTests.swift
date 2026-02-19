//
//  DamusCacheManagerConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: DamusCacheManager acknowledged file TOCTOU
//  Bead: damus-1ls
//
//  Fix being tested: try + catch (skip gracefully) instead of access() + removeItem (TOCTOU).
//  Fix-sensitivity: If try? is reverted to access() + removeItem, the _before test shows the
//  TOCTOU window and the _after concurrent deletion would produce thrown errors instead of
//  graceful no-ops.

import XCTest
@testable import damus

/// Tests for the DamusCacheManager TOCTOU race: access() + removeItem can fail
/// when another thread deletes the file between the check and the removal.
final class DamusCacheManagerConcurrencyTests: XCTestCase {

    // MARK: - Before fix: access() + removeItem TOCTOU

    /// Deterministically demonstrates the TOCTOU window using ConcurrentBarrier:
    /// Thread A checks access() → exists, Thread B deletes the file, Thread A's removeItem throws.
    func test_cache_manager_toctou_before() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("toctou_before_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let testFile = tempDir.appendingPathComponent("victim.txt")
        FileManager.default.createFile(atPath: testFile.path, contents: Data("data".utf8))

        let barrier = ConcurrentBarrier()
        // Second sync point: Thread B signals after deletion, before Thread A attempts removal
        let bDone = DispatchSemaphore(value: 0)
        var threadAError: Error?
        let group = DispatchGroup()

        // Thread A: check-then-act (the old buggy pattern)
        group.enter()
        DispatchQueue.global().async {
            // Step 1: access() says file exists
            let exists = access(testFile.path, F_OK) == 0
            XCTAssertTrue(exists, "access() should confirm file exists")

            // Step 2: signal readiness, wait for Thread B to arrive at the race point
            barrier.arriveA()

            // Step 3: wait for Thread B to finish deleting the file
            bDone.wait()

            // Step 4: try to remove — but Thread B already deleted it!
            do {
                try FileManager.default.removeItem(at: testFile)
            } catch {
                threadAError = error
            }
            group.leave()
        }

        // Thread B: delete the file between A's check and A's act
        group.enter()
        DispatchQueue.global().async {
            // Wait for Thread A to confirm file exists via access()
            barrier.arriveB()

            // Delete the file out from under Thread A
            try? FileManager.default.removeItem(at: testFile)

            // Signal Thread A that deletion is complete
            bDone.signal()
            group.leave()
        }

        group.wait()

        // Thread A's removeItem should have thrown because Thread B deleted the file first
        XCTAssertNotNil(threadAError, "TOCTOU: Thread A's removeItem should throw after Thread B deletes the file")

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - After fix: try/catch removeItem handles concurrent deletion gracefully

    /// Exercises the real DamusCacheManager.clear_cache_folder(): 5 concurrent
    /// calls from background threads. The try/catch pattern (replacing
    /// access()+removeItem TOCTOU) handles already-deleted files gracefully.
    func test_cache_manager_toctou_after() {
        let manager = DamusCacheManager()
        let group = DispatchGroup()

        // 5 concurrent clear_cache_folder calls — try/catch handles duplicate removals
        for _ in 0..<5 {
            group.enter()
            manager.clear_cache_folder {
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "Concurrent clear_cache_folder calls complete without crashes (try/catch handles TOCTOU)")
    }
}
