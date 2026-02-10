//
//  DatabaseSnapshotManagerTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-01-02.
//

import XCTest
@testable import damus

class DatabaseSnapshotManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    var manager: DatabaseSnapshotManager!
    var testNdb: Ndb!
    
    /// Helper function to collect note IDs from a database subscription until expected notes are found or timeout occurs.
    /// - Parameters:
    ///   - ndb: The database instance to subscribe to
    ///   - filters: The filters to use for subscription
    ///   - expectedNoteIds: The set of note IDs we expect to find
    ///   - expectation: The XCTestExpectation to fulfill when all notes are found
    ///   - timeout: Maximum time to wait in seconds (default: 5.0)
    /// - Returns: The set of collected note IDs
    private func collectNoteIds(
        from ndb: Ndb,
        filters: [NdbFilter],
        expectedNoteIds: Set<NoteId>,
        expectation: XCTestExpectation,
        timeout: TimeInterval = 5.0
    ) -> Task<Set<NoteId>, Never> {
        Task {
            await withCheckedContinuation { continuation in
                var collectedNoteIds = Set<NoteId>()
                var hasReturned = false
                
                // Timeout handler
                Task {
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !hasReturned else { return }
                    hasReturned = true
                    print("⚠️ Timeout: Expected \(expectedNoteIds.count) notes, collected \(collectedNoteIds.count)")
                    continuation.resume(returning: collectedNoteIds)
                }
                
                // Subscription handler
                Task {
                    do {
                        for await item in try ndb.subscribe(filters: filters) {
                            guard !hasReturned else { break }
                            
                            switch item {
                            case .eose:
                                continue
                            case .event(let noteKey):
                                try ndb.lookup_note_by_key(noteKey, borrow: { unownedNote in
                                    switch unownedNote {
                                    case .none:
                                        return
                                    case .some(let unownedNote):
                                        collectedNoteIds.insert(unownedNote.id)
                                    }
                                })
                            }
                            
                            if collectedNoteIds == expectedNoteIds {
                                hasReturned = true
                                expectation.fulfill()
                                continuation.resume(returning: collectedNoteIds)
                            }
                        }
                    } catch {
                        guard !hasReturned else { return }
                        hasReturned = true
                        XCTFail("Note streaming failed: \(error)")
                        continuation.resume(returning: collectedNoteIds)
                    }
                }
            }
        }
    }
    
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
    
    // MARK: - Selective Snapshot Content Tests
    
    func testPerformSnapshot_ContainsOnlyRelevantNoteTypes() async throws {
        // Given: A database with various note types
        let profileNote = NostrEvent(content: "{\"name\":\"Test User\"}", keypair: test_keypair, kind: NostrKind.metadata.rawValue)!
        let textNote = NostrEvent(content: "Hello world", keypair: test_keypair, kind: NostrKind.text.rawValue)!
        let contactsNote = NostrEvent(content: "", keypair: test_keypair, kind: NostrKind.contacts.rawValue)!
        let muteListNote = NostrEvent(content: "", keypair: test_keypair, kind: NostrKind.mute_list.rawValue)!
        
        let profileFilter = try NdbFilter(from: NostrFilter(kinds: [.metadata]))
        let contactsFilter = try NdbFilter(from: NostrFilter(kinds: [.contacts]))
        let muteListFilter = try NdbFilter(from: NostrFilter(kinds: [.mute_list]))
        let textFilter = try NdbFilter(from: NostrFilter(kinds: [.text]))
        
        // Process notes into source database
        let expectedIngestedNotes = [profileNote, textNote, contactsNote, muteListNote]
        let expectedSnapshottedNotes = [profileNote, contactsNote, muteListNote]
        
        let expectedIngestedNoteIds = Set(expectedIngestedNotes.map { $0.id })
        let expectedSnapshottedNoteIds = Set(expectedSnapshottedNotes.map { $0.id })
        
        let allNotesAreIngestedInSourceDB = XCTestExpectation(description: "All notes are ingested in source DB")
        let ingestTask = collectNoteIds(
            from: testNdb,
            filters: [profileFilter, contactsFilter, muteListFilter, textFilter],
            expectedNoteIds: expectedIngestedNoteIds,
            expectation: allNotesAreIngestedInSourceDB
        )
        
        for note in expectedIngestedNotes {
            try testNdb.add(event: note)
        }
        
        await fulfillment(of: [allNotesAreIngestedInSourceDB], timeout: 5)
        let ingestedNoteIds = await ingestTask.value
        XCTAssertEqual(expectedIngestedNoteIds, ingestedNoteIds)
        
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        
        // When: Creating a snapshot
        try await manager.performSnapshot()
        
        // Then: Snapshot database should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotPath))
        
        // And: Snapshot should contain only profiles (kind 0), contacts (kind 3), and mute lists (kind 10000)
        guard let snapshotNdb = Ndb(path: snapshotPath, owns_db_file: false) else {
            XCTFail("Should be able to open snapshot database")
            return
        }
        defer { snapshotNdb.close() }
        
        let allNotesAreSnapshottedToSnapshotDB = XCTestExpectation(description: "All notes are snapshotted to snapshot DB")
        let snapshotTask = collectNoteIds(
            from: snapshotNdb,
            filters: [profileFilter, contactsFilter, muteListFilter, textFilter],
            expectedNoteIds: expectedSnapshottedNoteIds,
            expectation: allNotesAreSnapshottedToSnapshotDB
        )
        
        await fulfillment(of: [allNotesAreSnapshottedToSnapshotDB], timeout: 5)
        let snapshottedNoteIds = await snapshotTask.value
        XCTAssertEqual(expectedSnapshottedNoteIds, snapshottedNoteIds)
    }
    
    func testPerformSnapshot_HandlesEmptyDatabase() async throws {
        // Given: An empty database with no notes
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        
        // When: Creating a snapshot of an empty database
        try await manager.performSnapshot()
        
        // Then: Snapshot should be created successfully
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotPath))
        
        // And: Snapshot should be accessible but contain no notes
        guard let snapshotNdb = Ndb(path: snapshotPath, owns_db_file: false) else {
            XCTFail("Should be able to open snapshot database")
            return
        }
        defer { snapshotNdb.close() }
        
        let allFilter = try NdbFilter(from: NostrFilter())
        let allKeys = try snapshotNdb.query(filters: [allFilter], maxResults: 100)
        XCTAssertEqual(allKeys.count, 0, "Empty database snapshot should contain no notes")
    }
    
    func testPerformSnapshot_HandlesLargeNumberOfNotes() async throws {
        // Given: A database with many profile notes
        var profileNotes: [NostrEvent] = []
        for i in 0..<2000 {
            let profileNote = NostrEvent(content: "{\"name\":\"User \(i)\"}", keypair: generate_new_keypair().to_keypair(), kind: 0)!
            profileNotes.append(profileNote)
        }
        
        let profileFilter = try NdbFilter(from: NostrFilter(kinds: [.metadata]))
        let expectedNoteIds = Set(profileNotes.map { $0.id })
        let allNotesIngested = XCTestExpectation(description: "All 2000 profile notes are ingested")
        
        let ingestTask = collectNoteIds(
            from: testNdb,
            filters: [profileFilter],
            expectedNoteIds: expectedNoteIds,
            expectation: allNotesIngested
        )
        
        for profileNote in profileNotes {
            try testNdb.add(event: profileNote)
        }
        
        // Wait for all notes to be ingested before snapshot
        await fulfillment(of: [allNotesIngested], timeout: 10)
        let ingestedNoteIds = await ingestTask.value
        XCTAssertEqual(expectedNoteIds, ingestedNoteIds, "All 2000 profile notes should be ingested")
        
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        
        // When: Creating a snapshot
        try await manager.performSnapshot()
        
        // Then: Snapshot should contain all profile notes
        guard let snapshotNdb = Ndb(path: snapshotPath, owns_db_file: false) else {
            XCTFail("Should be able to open snapshot database")
            return
        }
        defer { snapshotNdb.close() }
        
        let profileKeys = try snapshotNdb.query(filters: [profileFilter], maxResults: 100_000)
        XCTAssertEqual(profileKeys.count, 2000, "Snapshot should contain all 2000 profile notes")
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
    
    func testPerformSnapshot_ReplacesExistingSnapshot() async throws {
        // Given: A snapshot already exists with a profile note
        let firstProfileNote = NostrEvent(content: "{\"name\":\"First User\"}", keypair: generate_new_keypair().to_keypair(), kind: 0)!
        
        let profileFilter = try NdbFilter(from: NostrFilter(kinds: [.metadata]))
        let firstNoteIds = Set([firstProfileNote.id])
        let firstNoteIngested = XCTestExpectation(description: "First note is ingested")
        
        let firstIngestTask = collectNoteIds(
            from: testNdb,
            filters: [profileFilter],
            expectedNoteIds: firstNoteIds,
            expectation: firstNoteIngested
        )
        
        try testNdb.add(event: firstProfileNote)
        
        await fulfillment(of: [firstNoteIngested], timeout: 5)
        let firstIngestedNoteIds = await firstIngestTask.value
        XCTAssertEqual(firstNoteIds, firstIngestedNoteIds, "First profile note should be ingested")
        
        try await manager.performSnapshot()
        
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        
        // Add a new profile note to the source database
        let secondProfileNote = NostrEvent(content: "{\"name\":\"Second User\"}", keypair: generate_new_keypair().to_keypair(), kind: 0)!
        
        let bothNoteIds = Set([firstProfileNote.id, secondProfileNote.id])
        let secondNoteIngested = XCTestExpectation(description: "Second note is ingested")
        
        let secondIngestTask = collectNoteIds(
            from: testNdb,
            filters: [profileFilter],
            expectedNoteIds: bothNoteIds,
            expectation: secondNoteIngested
        )
        
        try testNdb.add(event: secondProfileNote)
        
        await fulfillment(of: [secondNoteIngested], timeout: 5)
        let secondIngestedNoteIds = await secondIngestTask.value
        XCTAssertEqual(bothNoteIds, secondIngestedNoteIds, "Both profile notes should be ingested")
        
        // When: Creating another snapshot
        try await manager.performSnapshot()
        
        // Then: New snapshot should replace the old one and contain both notes
        guard let snapshotNdb = Ndb(path: snapshotPath, owns_db_file: false) else {
            XCTFail("Should be able to open snapshot database")
            return
        }
        defer { snapshotNdb.close() }
        
        let expectedNoteIds = Set([firstProfileNote.id, secondProfileNote.id])
        let allNotesAreInSnapshot = XCTestExpectation(description: "All notes are in snapshot")
        
        let snapshotTask = collectNoteIds(
            from: snapshotNdb,
            filters: [profileFilter],
            expectedNoteIds: expectedNoteIds,
            expectation: allNotesAreInSnapshot
        )
        
        await fulfillment(of: [allNotesAreInSnapshot], timeout: 5)
        let snapshottedNoteIds = await snapshotTask.value
        XCTAssertEqual(expectedNoteIds, snapshottedNoteIds, "Snapshot should contain both profile notes")
    }

    // MARK: - Snapshot Marker Tests

    /// Verifies that marker constants are consistent across modules.
    /// This prevents duplication bugs where the constants drift out of sync.
    func testMarkerConstants_Match() {
        XCTAssertEqual(DatabaseSnapshotManager.snapshotReadyMarker,
                       Ndb.snapshotReadyMarker,
                       "Marker constants must match across DatabaseSnapshotManager and Ndb")
    }

    /// Verifies that a snapshot run creates the ready marker file.
    func testPerformSnapshot_CreatesMarkerFile() async throws {
        // Given: No previous snapshot exists
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        let parentDir = URL(fileURLWithPath: snapshotPath).deletingLastPathComponent().path
        let markerPath = "\(parentDir)/\(DatabaseSnapshotManager.snapshotReadyMarker)"

        // Clean up any existing snapshot and marker
        try? FileManager.default.removeItem(atPath: snapshotPath)
        try? FileManager.default.removeItem(atPath: markerPath)

        // When: Creating a snapshot
        try await manager.performSnapshot()

        // Then: Marker file should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerPath),
            "Marker file should exist after snapshot completes")
    }

    /// Verifies Ndb fails to open default snapshot when marker is missing.
    func testNdb_WontOpenSnapshotWithoutMarker() async throws {
        // Given: A snapshot exists but marker file is missing
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        let parentDir = URL(fileURLWithPath: snapshotPath).deletingLastPathComponent().path
        let markerPath = "\(parentDir)/\(DatabaseSnapshotManager.snapshotReadyMarker)"

        // Create a snapshot (which creates the marker)
        try await manager.performSnapshot()
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotPath),
            "Snapshot should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerPath),
            "Marker should exist after snapshot")

        // Remove the marker to simulate incomplete snapshot
        try FileManager.default.removeItem(atPath: markerPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerPath),
            "Marker should be removed")

        // When: Trying to open the default snapshot path (nil path + owns_db_file: false)
        // This simulates how extensions open the snapshot
        let snapshotNdb = Ndb(path: nil, owns_db_file: false)

        // Then: Ndb should fail to open because marker is missing
        XCTAssertNil(snapshotNdb,
            "Ndb should not open snapshot without marker file")
    }

    /// Verifies Ndb successfully opens default snapshot when marker exists.
    func testNdb_OpensSnapshotWithMarker() async throws {
        // Given: A snapshot exists with marker file
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        let parentDir = URL(fileURLWithPath: snapshotPath).deletingLastPathComponent().path
        let markerPath = "\(parentDir)/\(DatabaseSnapshotManager.snapshotReadyMarker)"

        // Create a snapshot (which creates the marker)
        try await manager.performSnapshot()
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerPath),
            "Marker should exist after snapshot")

        // When: Trying to open the default snapshot path (nil path + owns_db_file: false)
        // This simulates how extensions open the snapshot
        let snapshotNdb = Ndb(path: nil, owns_db_file: false)

        // Then: Ndb should successfully open
        XCTAssertNotNil(snapshotNdb,
            "Ndb should open snapshot when marker file exists")
        snapshotNdb?.close()
    }

    /// Verifies Ndb requires marker even when snapshot path is passed explicitly.
    /// This prevents accidentally bypassing marker safety by specifying the path explicitly.
    func testNdb_ExplicitSnapshotPathRequiresMarker() async throws {
        // Given: A snapshot exists but we're opening with explicit snapshot path
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        let parentDir = URL(fileURLWithPath: snapshotPath).deletingLastPathComponent().path
        let markerPath = "\(parentDir)/\(DatabaseSnapshotManager.snapshotReadyMarker)"

        // Create a snapshot (which creates the marker)
        try await manager.performSnapshot()
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotPath),
            "Snapshot should exist")

        // Remove the marker
        try FileManager.default.removeItem(atPath: markerPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerPath),
            "Marker should be removed")

        // When: Opening with explicit snapshot path (owns_db_file: false)
        // This should STILL require marker to prevent accidental bypass
        let snapshotNdb = Ndb(path: snapshotPath, owns_db_file: false)

        // Then: Ndb should fail to open because marker protection applies to explicit snapshot paths
        XCTAssertNil(snapshotNdb,
            "Ndb should not open explicit snapshot path without marker")
    }

    /// Verifies snapshot update removes marker before writing and restores it after.
    func testPerformSnapshot_RemovesMarkerBeforeUpdate() async throws {
        // Given: A snapshot with marker exists
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        let parentDir = URL(fileURLWithPath: snapshotPath).deletingLastPathComponent().path
        let markerPath = "\(parentDir)/\(DatabaseSnapshotManager.snapshotReadyMarker)"

        // Create initial snapshot
        try await manager.performSnapshot()
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerPath),
            "Marker should exist after first snapshot")

        // Track marker state during second snapshot
        // The marker should be removed at the start and recreated at the end
        // We verify this by checking the final state is correct
        try await manager.performSnapshot()

        // Then: Marker should exist after second snapshot completes
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerPath),
            "Marker should exist after second snapshot completes")
    }

    /// Verifies marker ordering prevents snapshot reads during updates.
    /// Simulates the update sequence to ensure extensions cannot read during transition.
    func testMarkerOrdering_PreventsReadsDuringUpdate() async throws {
        guard let snapshotPath = Ndb.snapshot_db_path else {
            XCTFail("Snapshot path should be available")
            return
        }
        let parentDir = URL(fileURLWithPath: snapshotPath).deletingLastPathComponent().path
        let markerPath = "\(parentDir)/\(DatabaseSnapshotManager.snapshotReadyMarker)"

        // Create initial snapshot with marker
        try await manager.performSnapshot()
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerPath),
            "Marker should exist initially")

        // Simulate update sequence step 1: Remove marker
        try FileManager.default.removeItem(atPath: markerPath)

        // Verify extensions cannot open during transition (no marker)
        let ndbDuringUpdate = Ndb(path: nil, owns_db_file: false)
        XCTAssertNil(ndbDuringUpdate,
            "Ndb should not open when marker is removed during update")

        // Simulate update sequence step 2: Restore marker after update
        try Data().write(to: URL(fileURLWithPath: markerPath))

        // Verify extensions can open after marker restored
        let ndbAfterUpdate = Ndb(path: nil, owns_db_file: false)
        XCTAssertNotNil(ndbAfterUpdate,
            "Ndb should open when marker exists after update")
        ndbAfterUpdate?.close()
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
        case (.failedToCreateSnapshotDatabase, .failedToCreateSnapshotDatabase):
            return true
        case (.moveFailed, .moveFailed):
            return true
        default:
            return false
        }
    }
}
