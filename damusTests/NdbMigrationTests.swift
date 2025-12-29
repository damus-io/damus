//
//  NdbMigrationTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-01-02.
//

import XCTest
@testable import damus

final class NdbMigrationTests: XCTestCase {
    
    var testDirectory: URL!
    var legacyPath: String!
    var privatePath: String!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a temporary directory for tests
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NdbMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        
        // Set up test paths
        legacyPath = testDirectory.appendingPathComponent("legacy").path
        privatePath = testDirectory.appendingPathComponent("private").path
    }
    
    override func tearDown() async throws {
        // Clean up test directory
        if let testDirectory = testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Creates mock database files in the specified directory
    /// - Parameters:
    ///   - path: The directory path where database files should be created
    ///   - content: The content to write to the database files. If nil, uses a default content string
    ///   - modificationDate: The modification date to set on the data.mdb file
    private func createMockDatabaseFiles(at path: String, content: String? = nil, modificationDate: Date = Date()) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        
        // Create both data.mdb and lock.mdb files
        let dataMdbPath = "\(path)/data.mdb"
        let lockMdbPath = "\(path)/lock.mdb"
        
        // Write content (use provided content or default)
        let fileContent = content ?? "Mock database content"
        let dummyData = fileContent.data(using: .utf8)!
        try dummyData.write(to: URL(fileURLWithPath: dataMdbPath))
        try dummyData.write(to: URL(fileURLWithPath: lockMdbPath))
        
        // Set modification date
        try fileManager.setAttributes([.modificationDate: modificationDate], ofItemAtPath: dataMdbPath)
    }
    
    /// Verifies that database files exist at the specified path
    private func verifyDatabaseFilesExist(at path: String) -> Bool {
        let fileManager = FileManager.default
        let dataMdbExists = fileManager.fileExists(atPath: "\(path)/data.mdb")
        let lockMdbExists = fileManager.fileExists(atPath: "\(path)/lock.mdb")
        return dataMdbExists && lockMdbExists
    }
    
    /// Verifies that database files exist at the specified path
    private func verifyDataDotMdbExists(at path: String) -> Bool {
        let fileManager = FileManager.default
        let dataMdbExists = fileManager.fileExists(atPath: "\(path)/data.mdb")
        return dataMdbExists
    }
    
    /// Verifies that database files do not exist at the specified path
    private func verifyDatabaseFilesDoNotExist(at path: String) -> Bool {
        let fileManager = FileManager.default
        let dataMdbExists = fileManager.fileExists(atPath: "\(path)/data.mdb")
        let lockMdbExists = fileManager.fileExists(atPath: "\(path)/lock.mdb")
        return !dataMdbExists && !lockMdbExists
    }
    
    // MARK: - Tests
    
    func testDbMigrateIfNeeded_migratesFromLegacyToPrivate() throws {
        // Given: Legacy database files exist with a newer modification date than private
        let legacyModificationDate = Date()
        let legacyContent = "Legacy database content"
        try createMockDatabaseFiles(at: legacyPath, content: legacyContent, modificationDate: legacyModificationDate)
        
        // Verify initial state: legacy files exist, private files don't
        XCTAssertTrue(verifyDatabaseFilesExist(at: legacyPath), "Legacy database files should exist before migration")
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: privatePath), "Private database files should not exist before migration")
        
        // When: Migration is triggered
        try Ndb.migrate_db_location_if_needed(db_path: privatePath, legacy_path: legacyPath)
        
        // Then: Files should be migrated to private path
        XCTAssertTrue(verifyDatabaseFilesExist(at: privatePath), "Private database files should exist after migration")
        
        // Verify the content was actually copied/moved
        let privateDataContent = try String(contentsOfFile: "\(privatePath!)/data.mdb")
        XCTAssertEqual(privateDataContent, legacyContent, "Migrated database content should match original")
        
        // The original files should be gone (moved, not copied)
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: legacyPath), "Legacy database files should not exist after migration (files should be moved, not copied)")
    }
    
    func testDbMigrateIfNeeded_noMigrationWhenPrivateHasLatestFiles() throws {
        // Given: Both locations have database files, but private has a newer modification date
        let legacyModificationDate = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let privateModificationDate = Date() // Now (newer)
        
        let legacyContent = "Legacy database content"
        let privateContent = "Private database content (newer)"
        
        try createMockDatabaseFiles(at: legacyPath, content: legacyContent, modificationDate: legacyModificationDate)
        try createMockDatabaseFiles(at: privatePath, content: privateContent, modificationDate: privateModificationDate)
        
        // Store original private content to verify it doesn't change
        let originalPrivateContent = try String(contentsOfFile: "\(privatePath!)/data.mdb")
        XCTAssertEqual(originalPrivateContent, privateContent, "Initial private content should match")
        
        // When: Migration is triggered
        try Ndb.migrate_db_location_if_needed(db_path: privatePath, legacy_path: legacyPath)
        
        // Then: Old files should be deleted to preserve storage
        XCTAssertTrue(verifyDatabaseFilesExist(at: privatePath), "Private database files should still exist")
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: legacyPath), "Legacy database files should not still exist, to save storage space (deleted)")
        
        let currentPrivateContent = try String(contentsOfFile: "\(privatePath!)/data.mdb")
        XCTAssertEqual(currentPrivateContent, privateContent, "Private database content should be unchanged")
        XCTAssertNotEqual(currentPrivateContent, legacyContent, "Private content should not have been replaced with legacy content")
    }
    
    func testDbMigrateIfNeeded_noMigrationWhenOnlyPrivateFilesExist() throws {
        // Given: Only private path has database files (no legacy files)
        let privateModificationDate = Date()
        let privateContent = "Private database content only"
        try createMockDatabaseFiles(at: privatePath, content: privateContent, modificationDate: privateModificationDate)
        
        // Verify initial state
        XCTAssertTrue(verifyDatabaseFilesExist(at: privatePath), "Private database files should exist")
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: legacyPath), "Legacy database files should not exist")
        
        let originalContent = try String(contentsOfFile: "\(privatePath!)/data.mdb")
        
        // When: Migration is triggered
        try Ndb.migrate_db_location_if_needed(db_path: privatePath, legacy_path: legacyPath)
        
        // Then: Nothing should change
        XCTAssertTrue(verifyDatabaseFilesExist(at: privatePath), "Private database files should still exist")
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: legacyPath), "Legacy database files should still not exist")
        
        let currentContent = try String(contentsOfFile: "\(privatePath!)/data.mdb")
        XCTAssertEqual(currentContent, originalContent, "Private content should remain unchanged")
    }
    
    func testDbMigrateIfNeeded_noMigrationWhenNoDatabaseFilesExist() throws {
        // Given: No database files exist in either location (fresh install)
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: privatePath), "Private database files should not exist")
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: legacyPath), "Legacy database files should not exist")
        
        // When: Migration is triggered
        try Ndb.migrate_db_location_if_needed(db_path: privatePath, legacy_path: legacyPath)
        
        // Then: Nothing should happen, no files should be created
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: privatePath), "Private database files should still not exist")
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: legacyPath), "Legacy database files should still not exist")
    }
    
    func testDbMigrateIfNeeded_replacesExistingPrivateFilesWithNewerLegacyFiles() throws {
        // Given: Both locations have database files, but legacy has newer files
        let privateModificationDate = Date(timeIntervalSinceNow: -3600) // 1 hour ago (older)
        let legacyModificationDate = Date() // Now (newer)
        
        let oldPrivateContent = "Old private database content"
        let newLegacyContent = "New legacy database content"
        
        try createMockDatabaseFiles(at: privatePath, content: oldPrivateContent, modificationDate: privateModificationDate)
        try createMockDatabaseFiles(at: legacyPath, content: newLegacyContent, modificationDate: legacyModificationDate)
        
        // Verify initial state
        let initialPrivateContent = try String(contentsOfFile: "\(privatePath!)/data.mdb")
        XCTAssertEqual(initialPrivateContent, oldPrivateContent, "Private should have old content initially")
        
        // When: Migration is triggered
        try Ndb.migrate_db_location_if_needed(db_path: privatePath, legacy_path: legacyPath)
        
        // Then: Private files should be replaced with legacy content
        XCTAssertTrue(verifyDatabaseFilesExist(at: privatePath), "Private database files should exist")
        
        let finalPrivateContent = try String(contentsOfFile: "\(privatePath!)/data.mdb")
        XCTAssertEqual(finalPrivateContent, newLegacyContent, "Private database should now contain the newer legacy content")
        XCTAssertNotEqual(finalPrivateContent, oldPrivateContent, "Old private content should be replaced")
        
        // Legacy files should be gone (moved, not copied)
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: legacyPath), "Legacy database files should not exist after migration")
    }
    
    func testDbMigrateIfNeeded_migratesPartialDatabaseFiles() throws {
        // Given: Legacy location has only one database file (data.mdb but no lock.mdb)
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: legacyPath, withIntermediateDirectories: true)
        
        // Create only data.mdb
        let partialContent = "Partial database content"
        try partialContent.data(using: .utf8)!.write(to: URL(fileURLWithPath: "\(legacyPath!)/data.mdb"))
        
        // Verify initial state - only one file exists
        XCTAssertTrue(fileManager.fileExists(atPath: "\(legacyPath!)/data.mdb"), "data.mdb should exist")
        XCTAssertFalse(fileManager.fileExists(atPath: "\(legacyPath!)/lock.mdb"), "lock.mdb should not exist")
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: privatePath), "Private database files should not exist")
        
        // When: Migration is triggered
        try Ndb.migrate_db_location_if_needed(db_path: privatePath, legacy_path: legacyPath)
        
        // Then: The partial file SHOULD be migrated
        XCTAssertTrue(verifyDataDotMdbExists(at: privatePath), "Private database files should exist (partial migration should occur)")
        XCTAssertFalse(fileManager.fileExists(atPath: "\(legacyPath!)/data.mdb"), "Legacy data.mdb should not still exist")
    }
    
    func testDbMigrateIfNeeded_migratesWhenPrivatePathDoesNotExist() throws {
        // Given: Legacy files exist, but private directory doesn't exist yet
        let legacyModificationDate = Date()
        let legacyContent = "Legacy database content for new migration"
        try createMockDatabaseFiles(at: legacyPath, content: legacyContent, modificationDate: legacyModificationDate)
        
        let fileManager = FileManager.default
        
        // Verify initial state
        XCTAssertTrue(verifyDatabaseFilesExist(at: legacyPath), "Legacy database files should exist")
        XCTAssertFalse(fileManager.fileExists(atPath: privatePath), "Private directory should not exist yet")
        
        // When: Migration is triggered
        try Ndb.migrate_db_location_if_needed(db_path: privatePath, legacy_path: legacyPath)
        
        // Then: Private directory should be created and files should be migrated
        XCTAssertTrue(fileManager.fileExists(atPath: privatePath), "Private directory should now exist")
        XCTAssertTrue(verifyDatabaseFilesExist(at: privatePath), "Private database files should exist after migration")
        
        // Verify content was migrated correctly
        let privateDataContent = try String(contentsOfFile: "\(privatePath!)/data.mdb")
        XCTAssertEqual(privateDataContent, legacyContent, "Migrated database content should match original")
        
        // Legacy files should be gone (moved)
        XCTAssertTrue(verifyDatabaseFilesDoNotExist(at: legacyPath), "Legacy database files should not exist after migration")
    }
}
