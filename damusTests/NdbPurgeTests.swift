//
//  NdbPurgeTests.swift
//  damus
//

import XCTest
@testable import damus

final class NdbPurgeTests: XCTestCase {

    var testDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NdbPurgeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        // Ensure flags and snapshot timestamp are cleared before each test.
        UserDefaults.standard.set(false, forKey: Ndb.purge_on_next_launch_key)
        UserDefaults.standard.set(false, forKey: Ndb.compact_on_next_launch_key)
        UserDefaults.standard.removeObject(forKey: "lastDatabaseSnapshotDate")
    }

    override func tearDown() async throws {
        if let testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        // Leave flags and snapshot timestamp cleared after each test.
        UserDefaults.standard.set(false, forKey: Ndb.purge_on_next_launch_key)
        UserDefaults.standard.set(false, forKey: Ndb.compact_on_next_launch_key)
        UserDefaults.standard.removeObject(forKey: "lastDatabaseSnapshotDate")
        try await super.tearDown()
    }

    // MARK: - set_purge_on_next_launch

    func testSetPurgeOnNextLaunch_setsUserDefaultsFlag() {
        // Given: the flag is not set
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Ndb.purge_on_next_launch_key))

        // When
        Ndb.set_purge_on_next_launch()

        // Then
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: Ndb.purge_on_next_launch_key),
            "set_purge_on_next_launch() should set the UserDefaults flag to true"
        )
    }

    /// Helper: path for an isolated snapshot directory inside the test directory.
    private var testSnapshotPath: String {
        testDirectory.appendingPathComponent("snapshot").path
    }

    // MARK: - purge_if_needed: flag not set

    func testPurgeIfNeeded_doesNothingWhenFlagNotSet() {
        // Given: the flag is false (set in setUp)
        let dbPath = testDirectory.path

        // When
        Ndb.purge_if_needed(db_path: dbPath, snapshot_db_path: testSnapshotPath)

        // Then: no files were touched, flag remains false
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: Ndb.purge_on_next_launch_key),
            "Flag should remain false when purge_if_needed does nothing"
        )
    }

    // MARK: - purge_if_needed: no database present

    func testPurgeIfNeeded_clearsFlagWhenNoDatabaseExists() {
        // Given: flag is set, but no data.mdb exists in the directory
        Ndb.set_purge_on_next_launch()
        let emptyPath = testDirectory.appendingPathComponent("empty_db").path
        try? FileManager.default.createDirectory(atPath: emptyPath, withIntermediateDirectories: true)

        // When
        Ndb.purge_if_needed(db_path: emptyPath, snapshot_db_path: testSnapshotPath)

        // Then: flag is cleared
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: Ndb.purge_on_next_launch_key),
            "purge_if_needed should clear the flag even when no database file exists"
        )
    }

    // MARK: - purge_if_needed: deletes files and clears flag

    func testPurgeIfNeeded_deletesFilesAndClearsFlag() {
        // Given: a real Ndb database and the purge flag is set
        let dbPath = testDirectory.appendingPathComponent("real_db").path
        try? FileManager.default.createDirectory(atPath: dbPath, withIntermediateDirectories: true)

        guard let ndb = Ndb(path: dbPath) else {
            XCTFail("Could not open Ndb at \(dbPath)")
            return
        }
        ndb.close()

        let dataPath = "\(dbPath)/data.mdb"
        let lockPath = "\(dbPath)/lock.mdb"
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataPath), "data.mdb should exist before purge")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockPath), "lock.mdb should exist before purge")

        Ndb.set_purge_on_next_launch()

        // When
        Ndb.purge_if_needed(db_path: dbPath, snapshot_db_path: testSnapshotPath)

        // Then: both db files are gone
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dataPath),
            "data.mdb should be deleted after purge"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: lockPath),
            "lock.mdb should be deleted after purge"
        )

        // And: the flag is cleared
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: Ndb.purge_on_next_launch_key),
            "purge_if_needed should clear the purge flag after deleting files"
        )
    }

    // MARK: - purge_if_needed: clears compact flag

    func testPurgeIfNeeded_clearsCompactFlag() {
        // Given: both purge and compact flags are set
        let dbPath = testDirectory.appendingPathComponent("compact_flag_db").path
        try? FileManager.default.createDirectory(atPath: dbPath, withIntermediateDirectories: true)

        guard let ndb = Ndb(path: dbPath) else {
            XCTFail("Could not open Ndb at \(dbPath)")
            return
        }
        ndb.close()

        Ndb.set_purge_on_next_launch()
        Ndb.set_compact_on_next_launch()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key))

        // When
        Ndb.purge_if_needed(db_path: dbPath, snapshot_db_path: testSnapshotPath)

        // Then: compact flag is also cleared
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key),
            "purge_if_needed should clear the compact flag because compaction is pointless after a purge"
        )
    }

    // MARK: - purge_if_needed: clears snapshot freshness timestamp

    func testPurgeIfNeeded_clearsSnapshotTimestamp() {
        // Given: a snapshot timestamp exists and the purge flag is set
        let snapshotDateKey = "lastDatabaseSnapshotDate"
        UserDefaults.standard.set(Date(), forKey: snapshotDateKey)
        XCTAssertNotNil(UserDefaults.standard.object(forKey: snapshotDateKey))

        let dbPath = testDirectory.appendingPathComponent("snapshot_ts_db").path
        try? FileManager.default.createDirectory(atPath: dbPath, withIntermediateDirectories: true)

        Ndb.set_purge_on_next_launch()

        // When
        Ndb.purge_if_needed(db_path: dbPath, snapshot_db_path: testSnapshotPath)

        // Then: the snapshot timestamp is cleared so a fresh snapshot is created immediately
        XCTAssertNil(
            UserDefaults.standard.object(forKey: snapshotDateKey),
            "purge_if_needed should clear the snapshot freshness timestamp so the snapshot manager rebuilds immediately"
        )
    }

    // MARK: - purge_if_needed: clears cache directories

    func testPurgeIfNeeded_clearsCacheDirectories() throws {
        let fm = FileManager.default

        // Set up a db path (purge_if_needed requires one)
        let dbPath = testDirectory.appendingPathComponent("cache_test_db").path
        try fm.createDirectory(atPath: dbPath, withIntermediateDirectories: true)

        // Create mock Caches directory with files
        let cachesDir = testDirectory.appendingPathComponent("Caches")
        let videoCacheDir = cachesDir.appendingPathComponent("video_cache")
        try fm.createDirectory(at: videoCacheDir, withIntermediateDirectories: true)
        let videoCacheFile = videoCacheDir.appendingPathComponent("video.mp4")
        try Data(repeating: 0xAB, count: 512).write(to: videoCacheFile)
        let relayLogFile = cachesDir.appendingPathComponent("relay.log")
        try Data(repeating: 0xCD, count: 128).write(to: relayLogFile)

        // Create mock app group ImageCache directory with files
        let appGroupCacheDir = testDirectory.appendingPathComponent("AppGroupImageCache")
        try fm.createDirectory(at: appGroupCacheDir, withIntermediateDirectories: true)
        let imageCacheFile = appGroupCacheDir.appendingPathComponent("image.png")
        try Data(repeating: 0xEF, count: 256).write(to: imageCacheFile)

        // Create mock temp directory with files
        let tempDir = testDirectory.appendingPathComponent("Temp")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent("staging.tmp")
        try Data(repeating: 0x00, count: 64).write(to: tempFile)

        // Verify all mock files exist before purge
        XCTAssertTrue(fm.fileExists(atPath: videoCacheFile.path), "video cache file should exist before purge")
        XCTAssertTrue(fm.fileExists(atPath: relayLogFile.path), "relay log file should exist before purge")
        XCTAssertTrue(fm.fileExists(atPath: imageCacheFile.path), "image cache file should exist before purge")
        XCTAssertTrue(fm.fileExists(atPath: tempFile.path), "temp file should exist before purge")

        Ndb.set_purge_on_next_launch()

        // When
        Ndb.purge_if_needed(
            db_path: dbPath,
            snapshot_db_path: testSnapshotPath,
            caches_dir_path: cachesDir.path,
            app_group_cache_path: appGroupCacheDir.path,
            temp_dir_path: tempDir.path
        )

        // Then: all cache files are deleted
        XCTAssertFalse(fm.fileExists(atPath: videoCacheFile.path), "video cache file should be deleted after purge")
        XCTAssertFalse(fm.fileExists(atPath: relayLogFile.path), "relay log file should be deleted after purge")
        XCTAssertFalse(fm.fileExists(atPath: imageCacheFile.path), "image cache file should be deleted after purge")
        XCTAssertFalse(fm.fileExists(atPath: tempFile.path), "temp file should be deleted after purge")

        // The directories themselves should still exist
        XCTAssertTrue(fm.fileExists(atPath: cachesDir.path), "Caches directory itself should not be deleted")
        XCTAssertTrue(fm.fileExists(atPath: appGroupCacheDir.path), "AppGroup ImageCache directory itself should not be deleted")
        XCTAssertTrue(fm.fileExists(atPath: tempDir.path), "Temp directory itself should not be deleted")
    }
}
