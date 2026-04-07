//
//  NdbCompactionTests.swift
//  damus
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
        // Reset scheduling-related keys so tests start from a clean state.
        UserDefaults.standard.removeObject(forKey: Ndb.auto_compact_schedule_key)
        UserDefaults.standard.removeObject(forKey: Ndb.last_compact_date_key)
    }

    override func tearDown() async throws {
        if let testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        // Leave the flag cleared after each test.
        UserDefaults.standard.set(false, forKey: Ndb.compact_on_next_launch_key)
        // Clean up scheduling keys.
        UserDefaults.standard.removeObject(forKey: Ndb.auto_compact_schedule_key)
        UserDefaults.standard.removeObject(forKey: Ndb.last_compact_date_key)
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

    // MARK: - compact_if_needed: lock.mdb removal

    func testCompactIfNeeded_removesLockFileAfterCompaction() {
        // Given: a real Ndb database that has been opened and closed (so lock.mdb exists)
        let dbPath = testDirectory.appendingPathComponent("lock_test_db").path
        try? FileManager.default.createDirectory(atPath: dbPath, withIntermediateDirectories: true)

        guard let ndb = Ndb(path: dbPath) else {
            XCTFail("Could not open Ndb at \(dbPath)")
            return
        }
        ndb.close()

        let lockPath = "\(dbPath)/lock.mdb"
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: lockPath),
            "lock.mdb should exist after opening and closing Ndb"
        )

        // When: compact_if_needed runs
        Ndb.set_compact_on_next_launch()
        Ndb.compact_if_needed(db_path: dbPath)

        // Then: lock.mdb should NOT exist (it was deleted during compaction)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: lockPath),
            "lock.mdb should be removed after compaction to prevent stale reader-table crashes"
        )

        // And: LMDB recreates a fresh lock.mdb when re-opened
        guard let reopenedNdb = Ndb(path: dbPath) else {
            XCTFail("Could not re-open Ndb after compaction — database may be corrupt")
            return
        }
        reopenedNdb.close()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: lockPath),
            "lock.mdb should be recreated by LMDB after opening the compacted database"
        )
    }

    // MARK: - AutoCompactSchedule: interval values

    func testAutoCompactSchedule_intervalValues() {
        XCTAssertEqual(AutoCompactSchedule.daily.interval,   60 * 60 * 24,       "daily interval should be 24 hours")
        XCTAssertEqual(AutoCompactSchedule.weekly.interval,  60 * 60 * 24 * 7,   "weekly interval should be 7 days")
        XCTAssertEqual(AutoCompactSchedule.monthly.interval, 60 * 60 * 24 * 30,  "monthly interval should be 30 days")
        XCTAssertNil(AutoCompactSchedule.never.interval,                          ".never should have no interval")
    }

    // MARK: - get/set auto-compact schedule

    func testGetAutoCompactSchedule_returnsWeeklyByDefault() {
        // No key stored → default should be .weekly
        XCTAssertEqual(Ndb.get_auto_compact_schedule(), .weekly)
    }

    func testSetAndGetAutoCompactSchedule_roundTrips() {
        for schedule in AutoCompactSchedule.allCases {
            Ndb.set_auto_compact_schedule(schedule)
            XCTAssertEqual(Ndb.get_auto_compact_schedule(), schedule,
                           "Round-trip failed for schedule: \(schedule)")
        }
    }

    // MARK: - schedule_auto_compact_if_needed

    func testScheduleAutoCompact_doesNothingWhenNever() {
        Ndb.set_auto_compact_schedule(.never)

        Ndb.schedule_auto_compact_if_needed()

        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key),
            "schedule=never should never set the compact flag"
        )
    }

    func testScheduleAutoCompact_setsFlag_whenIntervalHasElapsed() {
        // Given: schedule is weekly, last compaction was 8 days ago
        Ndb.set_auto_compact_schedule(.weekly)
        let eightDaysAgo = Date().addingTimeInterval(-(60 * 60 * 24 * 8))
        UserDefaults.standard.set(eightDaysAgo, forKey: Ndb.last_compact_date_key)

        // When
        Ndb.schedule_auto_compact_if_needed()

        // Then: flag should be set
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key),
            "compact flag should be set when scheduled interval has elapsed"
        )
    }

    func testScheduleAutoCompact_doesNotSetFlag_whenIntervalHasNotElapsed() {
        // Given: schedule is weekly, last compaction was 1 day ago
        Ndb.set_auto_compact_schedule(.weekly)
        let oneDayAgo = Date().addingTimeInterval(-(60 * 60 * 24))
        UserDefaults.standard.set(oneDayAgo, forKey: Ndb.last_compact_date_key)

        // When
        Ndb.schedule_auto_compact_if_needed()

        // Then: flag should NOT be set
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key),
            "compact flag should not be set when the scheduled interval has not yet elapsed"
        )
    }

    func testScheduleAutoCompact_setsFlag_whenNoLastCompactDate() {
        // Given: schedule is daily, no last compact date stored (first launch)
        Ndb.set_auto_compact_schedule(.daily)
        // last_compact_date_key is absent (cleaned in setUp)

        // When
        Ndb.schedule_auto_compact_if_needed()

        // Then: flag should be set (distantPast triggers compaction on first launch)
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: Ndb.compact_on_next_launch_key),
            "compact flag should be set on first launch (no previous compaction date)"
        )
    }

    // MARK: - compact_if_needed: records last compact date

    func testCompactIfNeeded_recordsLastCompactDate_afterSuccessfulCompaction() {
        let dbPath = testDirectory.appendingPathComponent("date_record_db").path
        try? FileManager.default.createDirectory(atPath: dbPath, withIntermediateDirectories: true)

        guard let ndb = Ndb(path: dbPath) else {
            XCTFail("Could not open Ndb at \(dbPath)")
            return
        }
        ndb.close()

        XCTAssertNil(Ndb.get_last_compact_date(), "No last compact date should exist before first compaction")

        Ndb.set_compact_on_next_launch()

        let beforeCompact = Date()
        Ndb.compact_if_needed(db_path: dbPath)
        let afterCompact = Date()

        guard let lastDate = Ndb.get_last_compact_date() else {
            XCTFail("Last compact date should be set after successful compaction")
            return
        }

        XCTAssertGreaterThanOrEqual(lastDate, beforeCompact, "last compact date should be >= time before compaction started")
        XCTAssertLessThanOrEqual(lastDate, afterCompact, "last compact date should be <= time after compaction ended")
    }
}
