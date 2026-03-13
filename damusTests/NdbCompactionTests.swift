//
//  NdbCompactionTests.swift
//  damus
//
//  Created by Copilot on 2026-03-13.
//

import XCTest
@testable import damus

final class NdbCompactionTests: XCTestCase {

    var testDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NdbCompactionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        // Ensure the flag is cleared before each test.
        UserDefaults.standard.set(false, forKey: Ndb.compact_on_next_launch_key)
    }

    override func tearDown() async throws {
        if let testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        // Leave the flag cleared after each test.
        UserDefaults.standard.set(false, forKey: Ndb.compact_on_next_launch_key)
        try await super.tearDown()
    }

    // MARK: - set_compact_on_next_launch

    func testSetCompactOnNextLaunch_setsUserDefaultsFlag() {
        // Given: the flag is not set
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key))

        // When
        Ndb.set_compact_on_next_launch()

        // Then
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key),
            "set_compact_on_next_launch() should set the UserDefaults flag to true"
        )
    }

    // MARK: - compact_if_needed: flag not set

    func testCompactIfNeeded_doesNothingWhenFlagNotSet() {
        // Given: the flag is false (set in setUp)
        let dbPath = testDirectory.path

        // When
        Ndb.compact_if_needed(db_path: dbPath)

        // Then: no temp directory was created, no files were touched
        let tempPath = "\(dbPath)/ndb_compact_temp"
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempPath),
            "compact_if_needed should not create a temp directory when the flag is not set"
        )
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key),
            "Flag should remain false when compact_if_needed does nothing"
        )
    }

    // MARK: - compact_if_needed: no database present

    func testCompactIfNeeded_clearsFlagWhenNoDatabaseExists() {
        // Given: flag is set, but no data.mdb exists in the directory
        Ndb.set_compact_on_next_launch()
        let emptyPath = testDirectory.appendingPathComponent("empty_db").path
        try? FileManager.default.createDirectory(atPath: emptyPath, withIntermediateDirectories: true)

        // When
        Ndb.compact_if_needed(db_path: emptyPath)

        // Then: flag is cleared, no temp directory left over
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key),
            "compact_if_needed should clear the flag even when no database file exists"
        )
        let tempPath = "\(emptyPath)/ndb_compact_temp"
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempPath),
            "No temp directory should remain after compact_if_needed with no DB"
        )
    }

    // MARK: - compact_if_needed: full round-trip

    func testCompactIfNeeded_compactsAndClearsFlagWithRealDatabase() {
        // Given: a real Ndb database and the compact flag is set
        let dbPath = testDirectory.appendingPathComponent("real_db").path
        try? FileManager.default.createDirectory(atPath: dbPath, withIntermediateDirectories: true)

        guard let ndb = Ndb(path: dbPath) else {
            XCTFail("Could not open Ndb at \(dbPath)")
            return
        }
        ndb.close()

        let originalSize = (try? FileManager.default.attributesOfItem(atPath: "\(dbPath)/data.mdb")[.size] as? Int) ?? 0
        XCTAssertGreaterThan(originalSize, 0, "A freshly created database should have a non-zero size")

        Ndb.set_compact_on_next_launch()

        // When
        Ndb.compact_if_needed(db_path: dbPath)

        // Then: the flag is cleared
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key),
            "compact_if_needed should clear the flag after a successful compaction"
        )

        // The compacted database must be a valid, openable Ndb
        guard let compactedNdb = Ndb(path: dbPath) else {
            XCTFail("Could not open Ndb after compaction — database may be corrupt")
            return
        }
        compactedNdb.close()

        // No leftover temp directory
        let tempPath = "\(dbPath)/ndb_compact_temp"
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempPath),
            "Temp directory should be cleaned up after successful compaction"
        )
    }
}
