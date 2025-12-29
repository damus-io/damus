//
//  DatabaseSnapshotManagerTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-01-02.
//

import XCTest
@testable import damus

final class DatabaseSnapshotManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    var manager: DatabaseSnapshotManager!
    var testNdb: Ndb!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, conformingTo: .directory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        self.testNdb = Ndb(path: test_ndb_dir(), owns_db_file: true)!
        
        // Create the manager
        manager = DatabaseSnapshotManager(ndb: self.testNdb)
        
        // Clear UserDefaults for consistent testing
        UserDefaults.standard.removeObject(forKey: "lastDatabaseSnapshotDate")
    }
    
    override func tearDown() async throws {
        // Clean up temporary directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        
        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: "lastDatabaseSnapshotDate")
        
        // Stop any running snapshots
        await manager.stopPeriodicSnapshots()
        
        manager = nil
        tempDirectory = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Snapshot Creation Tests
    
    func testCreateSnapshotIfNeeded_CreatesSnapshotWhenNeverCreatedBefore() async throws {
        // Given: No previous snapshot exists
        XCTAssertNil(UserDefaults.standard.object(forKey: "lastDatabaseSnapshotDate"))
        
        // When: createSnapshotIfNeeded is called
        try await manager.createSnapshotIfNeeded()
        
        // Then: A snapshot should be created
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "lastDatabaseSnapshotDate"))
    }
    
    func testCreateSnapshotIfNeeded_SkipsSnapshotWhenRecentSnapshotExists() async throws {
        // Given: A recent snapshot was just created
        UserDefaults.standard.set(Date(), forKey: "lastDatabaseSnapshotDate")
        
        // When: createSnapshotIfNeeded is called
        let snapshotMade = try await manager.createSnapshotIfNeeded()
        
        // Then: No snapshot should be created
        XCTAssertFalse(snapshotMade)
    }
    
    func testCreateSnapshotIfNeeded_CreatesSnapshotWhenIntervalHasPassed() async throws {
        // Given: A snapshot was created more than 1 hour ago
        let oldDate = Date().addingTimeInterval(-60 * 61) // 61 minutes ago
        UserDefaults.standard.set(oldDate, forKey: "lastDatabaseSnapshotDate")
        
        // When: createSnapshotIfNeeded is called
        let snapshotMade = try await manager.createSnapshotIfNeeded()
        
        // Then: A snapshot should be created
        XCTAssertTrue(snapshotMade)
        
        // And: The last snapshot date should be updated
        let lastDate = UserDefaults.standard.object(forKey: "lastDatabaseSnapshotDate") as? Date
        XCTAssertNotNil(lastDate)
        XCTAssertTrue(lastDate! > oldDate)
    }
    
    // MARK: - Perform Snapshot Tests
    
    func testPerformSnapshot_WritesFile() async throws {
        // Given: No previous snapshot exists
        XCTAssertNil(UserDefaults.standard.object(forKey: "lastDatabaseSnapshotDate"))
        let fileManager = FileManager.default
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        try fileManager.removeItem(atPath: snapshotPath)
        XCTAssertFalse(fileManager.fileExists(atPath: snapshotPath), "Snapshot directory should not exist at \(snapshotPath)")
        
        
        // When: Creating a snapshot
        let snapshotMade = try await manager.createSnapshotIfNeeded()
        
        // Then: Snapshot should be created
        XCTAssertTrue(snapshotMade)
        
        // And: The snapshot should be there
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: snapshotPath, isDirectory: &isDirectory)
        
        XCTAssertTrue(exists, "Snapshot directory should exist at \(snapshotPath)")
        XCTAssertTrue(isDirectory.boolValue, "Snapshot path should be a directory")
        
        // And: LMDB database files should exist
        let dataFile = "\(snapshotPath)/data.mdb"
        XCTAssertTrue(fileManager.fileExists(atPath: dataFile), "data.mdb should exist")
    }
    
    func testPerformSnapshot_UpdatesTimestamp() async throws {
        // Given: No previous snapshot
        XCTAssertNil(UserDefaults.standard.object(forKey: "lastDatabaseSnapshotDate"))
        
        let beforeDate = Date()
        
        // When: Performing a snapshot
        try await manager.performSnapshot()
        
        let afterDate = Date()
        
        // Then: The timestamp should be set and within the time window
        let savedDate = UserDefaults.standard.object(forKey: "lastDatabaseSnapshotDate") as? Date
        XCTAssertNotNil(savedDate)
        XCTAssertGreaterThanOrEqual(savedDate!, beforeDate)
        XCTAssertLessThanOrEqual(savedDate!, afterDate)
    }
    
    func testPerformSnapshot_CanBeCalledMultipleTimes() async throws {
        // Given: A snapshot already exists
        try await manager.performSnapshot()
        
        // When: Performing another snapshot (this should replace the old one)
        try await manager.performSnapshot()
        
        // Then: No error should occur
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "lastDatabaseSnapshotDate"))
    }
    
    // MARK: - Periodic Snapshot Timer Tests
    
    func testStartPeriodicSnapshots_StartsTimer() async throws {
        // Given: Manager is initialized
        
        
        // When: startPeriodicSnapshots is called
        await manager.startPeriodicSnapshots()
        
        // Give the timer task a moment to execute
        try await Task.sleep(for: .milliseconds(100))
        
        // Then: A snapshot should be attempted
        let tickCount = await manager.snapshotTimerTickCount
        XCTAssertGreaterThan(tickCount, 0)
    }
    
    func testStartPeriodicSnapshots_DoesNotStartMultipleTimes() async throws {
        // Given: Timer is already started
        await manager.startPeriodicSnapshots()
        
        // Give the timer a moment to start
        try await Task.sleep(for: .milliseconds(500))
        
        let firstTickCount = await manager.snapshotTimerTickCount
        
        // When: startPeriodicSnapshots is called again
        await manager.startPeriodicSnapshots()
        
        // Give it a moment
        try await Task.sleep(for: .milliseconds(500))
        
        let secondTickCount = await manager.snapshotTimerTickCount
        
        // Then: The tick count should not have increased significantly
        // (proving we didn't start a second timer)
        XCTAssertEqual(secondTickCount, firstTickCount, "Starting twice should not create multiple timers")
    }
    
    func testStopPeriodicSnapshots_StopsTimer() async throws {
        // Given: Timer is running
        await manager.startPeriodicSnapshots()
        
        // When: stopPeriodicSnapshots is called and stats are reset
        await manager.stopPeriodicSnapshots()
        await manager.resetStats()
        
        // Wait longer than the timer interval
        try await Task.sleep(for: .milliseconds(200))
        
        // Then: No more snapshots should be created
        let snapshotCount = await manager.snapshotCount
        XCTAssertEqual(snapshotCount, 0)
    }
    
    func testStopPeriodicSnapshots_CanBeCalledMultipleTimes() async throws {
        // Given: Timer is running
        await manager.startPeriodicSnapshots()
        
        // When: stopPeriodicSnapshots is called multiple times
        await manager.stopPeriodicSnapshots()
        await manager.stopPeriodicSnapshots()
        
        // Then: No crash should occur (test passes if we get here)
        XCTAssertTrue(true)
    }
    
    // MARK: - Integration Tests
    
    func testSnapshotLifecycle_StartStopRestart() async throws {
        // Given: A manager with valid configuration
        
        // When: Starting, stopping, and restarting the timer
        await manager.startPeriodicSnapshots()
        try await Task.sleep(for: .milliseconds(100))
        
        await manager.stopPeriodicSnapshots()
        
        await manager.startPeriodicSnapshots()
        try await Task.sleep(for: .milliseconds(1000))
        
        // Then: Snapshots should be created appropriately
        let snapshotCount = await manager.snapshotCount
        XCTAssertGreaterThan(snapshotCount, 0)
    }
    
    func testSnapshotTimestampUpdates() async throws {
        // Given: No previous snapshot
        XCTAssertNil(UserDefaults.standard.object(forKey: "lastDatabaseSnapshotDate"))
        
        // When: Creating first snapshot
        try await manager.performSnapshot()
        let firstDate = UserDefaults.standard.object(forKey: "lastDatabaseSnapshotDate") as? Date
        XCTAssertNotNil(firstDate)
        
        // Wait to ensure time difference
        try await Task.sleep(for: .milliseconds(500))
        
        // Force another snapshot by clearing the date
        UserDefaults.standard.removeObject(forKey: "lastDatabaseSnapshotDate")
        try await manager.performSnapshot()
        let secondDate = UserDefaults.standard.object(forKey: "lastDatabaseSnapshotDate") as? Date
        XCTAssertNotNil(secondDate)
        
        // Then: Second date should be after first date
        XCTAssertGreaterThan(secondDate!, firstDate!, "Second snapshot timestamp should be later than first")
    }
    
    // MARK: - Error Handling Tests
    
    func testCreateSnapshotIfNeeded_HandlesErrors() async throws {
        // This test verifies that errors from performSnapshot are propagated
        // We can't easily test the actual error cases without mocking,
        // but we verify the method signature allows throwing
        
        // Given: A recent snapshot exists
        UserDefaults.standard.set(Date(), forKey: "lastDatabaseSnapshotDate")
        
        // When: Attempting to create a snapshot (should skip)
        let result = try await manager.createSnapshotIfNeeded()
        
        // Then: Should return false without throwing
        XCTAssertFalse(result)
    }
    
    // MARK: - Edge Case Tests
    
    func testSnapshotInterval_BoundaryCondition() async throws {
        // Given: A snapshot was created exactly 1 hour ago (the minimum interval)
        let exactlyOneHourAgo = Date().addingTimeInterval(-60 * 60)
        UserDefaults.standard.set(exactlyOneHourAgo, forKey: "lastDatabaseSnapshotDate")
        
        // When: Attempting to create a snapshot at the exact boundary
        let shouldCreate = try await manager.createSnapshotIfNeeded()
        
        // Then: A snapshot should be created (>= rather than > comparison)
        XCTAssertTrue(shouldCreate, "Snapshot should be created when exactly at minimum interval")
    }
    
    func testSnapshotInterval_JustBeforeBoundary() async throws {
        // Given: A snapshot was created 59 minutes and 59 seconds ago (just before the interval)
        let justBeforeOneHour = Date().addingTimeInterval(-60 * 59 - 59)
        UserDefaults.standard.set(justBeforeOneHour, forKey: "lastDatabaseSnapshotDate")
        
        // When: Attempting to create a snapshot
        let shouldCreate = try await manager.createSnapshotIfNeeded()
        
        // Then: No snapshot should be created
        XCTAssertFalse(shouldCreate, "Snapshot should not be created before minimum interval")
    }
}


// MARK: - SnapshotError Equatable Conformance for Testing

extension SnapshotError: Equatable {
    public static func == (lhs: SnapshotError, rhs: SnapshotError) -> Bool {
        switch (lhs, rhs) {
        case (.pathsUnavailable, .pathsUnavailable):
            return true
        case (.copyFailed, .copyFailed):
            return true
        case (.removeFailed, .removeFailed):
            return true
        case (.directoryCreationFailed, .directoryCreationFailed):
            return true
        default:
            return false
        }
    }
}

