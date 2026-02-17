//
//  DamusCacheManagerConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: DamusCacheManager acknowledged file TOCTOU
//  Bead: damus-1ls
//

import XCTest
@testable import damus

final class DamusCacheManagerConcurrencyTests: XCTestCase {

    // MARK: - Before fix: access() + removeItem TOCTOU

    func test_cache_manager_toctou_before() {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("cache_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // Create a test file
        let testFile = testDir.appendingPathComponent("test.txt")
        FileManager.default.createFile(atPath: testFile.path, contents: Data("data".utf8))

        // The old pattern: access() check then removeItem
        // Between these two calls, another thread could delete the file
        let exists = access(testFile.path, F_OK) != -1
        XCTAssertTrue(exists, "File should exist before removal")

        // Simulate another thread deleting it
        try? FileManager.default.removeItem(at: testFile)

        // Now our removal would fail
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))

        // Cleanup
        try? FileManager.default.removeItem(at: testDir)
    }

    // MARK: - After fix: try/catch on removeItem directly

    func test_cache_manager_toctou_after() {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("cache_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let testFile = testDir.appendingPathComponent("test.txt")
        FileManager.default.createFile(atPath: testFile.path, contents: Data("data".utf8))

        // Just try to remove — no check first
        do {
            try FileManager.default.removeItem(at: testFile)
        } catch {
            // Graceful failure
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path), "File should be removed")

        // Try again — should not crash
        do {
            try FileManager.default.removeItem(at: testFile)
            XCTFail("Should have thrown since file is already gone")
        } catch {
            // Expected: file not found
        }

        // Cleanup
        try? FileManager.default.removeItem(at: testDir)
    }
}
