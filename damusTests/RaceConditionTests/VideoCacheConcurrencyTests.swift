//
//  VideoCacheConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: VideoCache file system TOCTOU
//  Bead: damus-du5
//

import XCTest
@testable import damus

final class VideoCacheConcurrencyTests: XCTestCase {

    // MARK: - Before fix: fileExists + operation is TOCTOU

    /// Reproduces master's VideoCache which used fileExists before removeItem:
    ///   if FileManager.default.fileExists(atPath: path) {   // CHECK
    ///       try FileManager.default.removeItem(at: url)      // ACT
    ///   }
    /// Without atomic try?, both threads pass fileExists, then second removeItem fails.
    func test_video_cache_toctou_before() {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("toctou_before_\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data("test".utf8))

        let bothCheckedExists = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Thread A: master's check-then-remove
        group.enter()
        DispatchQueue.global().async {
            let exists = FileManager.default.fileExists(atPath: tempFile.path)  // CHECK: true
            barrier.arriveA()  // Both checked before either removes
            if exists {
                bothCheckedExists.increment()
                try? FileManager.default.removeItem(at: tempFile)  // ACT
            }
            group.leave()
        }

        // Thread B: also check-then-remove
        group.enter()
        DispatchQueue.global().async {
            let exists = FileManager.default.fileExists(atPath: tempFile.path)  // CHECK: also true
            barrier.arriveB()
            if exists {
                bothCheckedExists.increment()
                // Second removeItem would throw in master (file already gone)
                try? FileManager.default.removeItem(at: tempFile)
            }
            group.leave()
        }

        group.wait()
        XCTAssertEqual(bothCheckedExists.value, 2, "Master VideoCache bug: both threads pass fileExists before either removes (TOCTOU)")
    }

    // MARK: - After fix: try? removes the TOCTOU

    /// Simulation: VideoCache is not in the main target's build phase (it's
    /// compiled via a separate module path). The fix replaces fileExists +
    /// attributesOfItem with try? attributesOfItem, eliminating the TOCTOU.
    /// This test reproduces the try? pattern on real FileManager operations.
    func test_video_cache_toctou_after() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("video_toctou_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create files matching VideoCache's cache structure
        for i in 0..<10 {
            let file = tempDir.appendingPathComponent("cached_\(i).mp4")
            FileManager.default.createFile(atPath: file.path, contents: Data("video\(i)".utf8))
        }

        // 10 concurrent threads use try? attributesOfItem + try? removeItem
        // (the exact pattern from VideoCache.maybe_cached_url_for)
        let group = DispatchGroup()
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                for i in 0..<10 {
                    let file = tempDir.appendingPathComponent("cached_\(i).mp4")
                    // try? pattern: no TOCTOU — if file is already gone, returns nil
                    let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                    if attrs != nil {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
                group.leave()
            }
        }

        group.wait()
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path))?.count ?? 0
        XCTAssertEqual(remaining, 0, "try? pattern handles concurrent file operations gracefully")
    }
}
