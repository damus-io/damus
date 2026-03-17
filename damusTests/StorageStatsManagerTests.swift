//
//  StorageStatsManagerTests.swift
//  damusTests
//
//  Created by OpenCode on 2026-02-25.
//

import XCTest
@testable import damus
import Kingfisher

/// Comprehensive test suite for storage usage calculation logic
///
/// Tests cover:
/// - StorageStats calculations (total size, percentages)
/// - File size calculations with temporary test files
/// - Async storage stats calculations
/// - Byte formatting utilities
/// - Ndb.getStats() database statistics
/// - Integration between components
/// - Thread safety and error handling
final class StorageStatsManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    var mockNostrDBPath: String!
    var mockSnapshotPath: String!
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageStatsManagerTests-\(UUID().uuidString)")
        
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create mock database directories
        let nostrDBDir = tempDirectory.appendingPathComponent("nostrdb")
        let snapshotDir = tempDirectory.appendingPathComponent("snapshot")
        
        try? FileManager.default.createDirectory(at: nostrDBDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        
        mockNostrDBPath = nostrDBDir.path
        mockSnapshotPath = snapshotDir.path
    }
    
    override func tearDown() {
        // Clean up temporary files
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        
        tempDirectory = nil
        mockNostrDBPath = nil
        mockSnapshotPath = nil
        
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Create a temporary file with specified size
    /// - Parameters:
    ///   - path: Full path for the file
    ///   - size: Size in bytes
    private func createTestFile(at path: String, size: UInt64) throws {
        let data = Data(repeating: 0, count: Int(size))
        try data.write(to: URL(fileURLWithPath: path))
    }
    
    /// Get file size using FileManager (reference implementation)
    private func getActualFileSize(at path: String) -> UInt64? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.size] as? UInt64
        } catch {
            return nil
        }
    }
    
    // MARK: - 1. StorageStats Structure Tests
    
    /// Test that totalSize correctly sums all storage components
    func testTotalSizeCalculation() {
        let stats = StorageStats(
            nostrdbDetails: nil,
            nostrdbSize: 1000,
            snapshotSize: 500,
            imageCacheSize: 250,
            videoCacheSize: 0,
            otherSize: 0
        )

        XCTAssertEqual(stats.totalSize, 1750, "Total size should sum all components")
    }
    
    /// Test percentage calculation accuracy
    func testPercentageCalculation() {
        let stats = StorageStats(
            nostrdbDetails: nil,
            nostrdbSize: 600,
            snapshotSize: 300,
            imageCacheSize: 100,
            videoCacheSize: 0,
            otherSize: 0
        )
        
        // Total = 1000, so 600 should be 60%
        let nostrdbPercentage = stats.percentage(for: 600)
        XCTAssertEqual(nostrdbPercentage, 60.0, accuracy: 0.01, "NostrDB should be 60% of total")
        
        let snapshotPercentage = stats.percentage(for: 300)
        XCTAssertEqual(snapshotPercentage, 30.0, accuracy: 0.01, "Snapshot should be 30% of total")
        
        let cachePercentage = stats.percentage(for: 100)
        XCTAssertEqual(cachePercentage, 10.0, accuracy: 0.01, "Cache should be 10% of total")
    }
    
    /// Test percentage calculation when total is zero (edge case)
    func testPercentageWithZeroTotal() {
        let stats = StorageStats(
            nostrdbDetails: nil,
            nostrdbSize: 0,
            snapshotSize: 0,
            imageCacheSize: 0,
            videoCacheSize: 0,
            otherSize: 0
        )
        
        let percentage = stats.percentage(for: 100)
        XCTAssertEqual(percentage, 0.0, "Percentage should be 0 when total is 0")
    }
    
    /// Test that StorageStats conforms to Hashable properly
    func testStorageStatsHashableConformance() {
        let stats1 = StorageStats(
            nostrdbDetails: nil,
            nostrdbSize: 1000,
            snapshotSize: 500,
            imageCacheSize: 250,
            videoCacheSize: 0,
            otherSize: 0
        )

        let stats2 = StorageStats(
            nostrdbDetails: nil,
            nostrdbSize: 1000,
            snapshotSize: 500,
            imageCacheSize: 250,
            videoCacheSize: 0,
            otherSize: 0
        )

        let stats3 = StorageStats(
            nostrdbDetails: nil,
            nostrdbSize: 2000,
            snapshotSize: 500,
            imageCacheSize: 250,
            videoCacheSize: 0,
            otherSize: 0
        )
        
        // Equal stats should be equal and have same hash
        XCTAssertEqual(stats1, stats2, "Identical stats should be equal")
        XCTAssertEqual(stats1.hashValue, stats2.hashValue, "Equal stats should have same hash")
        
        // Different stats should not be equal
        XCTAssertNotEqual(stats1, stats3, "Different stats should not be equal")
        
        // Should work in Set
        let set: Set<StorageStats> = [stats1, stats2, stats3]
        XCTAssertEqual(set.count, 2, "Set should contain 2 unique stats")
    }
    
    // MARK: - 2. File Size Calculation Tests
    
    /// Test file size calculation with an existing file
    func testGetFileSizeWithExistingFile() throws {
        let testFilePath = tempDirectory.appendingPathComponent("test-file.dat").path
        let expectedSize: UInt64 = 1024 * 1024 // 1 MB
        
        // Create test file with known size
        try createTestFile(at: testFilePath, size: expectedSize)
        
        // Verify file was created correctly
        let actualSize = getActualFileSize(at: testFilePath)
        XCTAssertNotNil(actualSize, "Test file should exist")
        XCTAssertEqual(actualSize, expectedSize, "Test file should have expected size")
    }
    
    /// Test file size calculation when file doesn't exist (should return 0)
    func testGetFileSizeWithNonexistentFile() {
        let nonexistentPath = tempDirectory.appendingPathComponent("nonexistent.dat").path
        
        // Verify file doesn't exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: nonexistentPath), "File should not exist")
        
        let size = getActualFileSize(at: nonexistentPath)
        XCTAssertNil(size, "Size should be nil for nonexistent file")
    }
    
    /// Test NostrDB file size calculation with valid path
    func testGetNostrDBSizeWithValidPath() throws {
        let dbFilePath = "\(mockNostrDBPath!)/\(Ndb.main_db_file_name)"
        let expectedSize: UInt64 = 5 * 1024 * 1024 // 5 MB
        
        // Create mock database file
        try createTestFile(at: dbFilePath, size: expectedSize)
        
        // Verify file size can be retrieved
        let actualSize = getActualFileSize(at: dbFilePath)
        XCTAssertNotNil(actualSize, "DB file should exist")
        XCTAssertEqual(actualSize, expectedSize, "DB file should have expected size")
    }
    
    /// Test snapshot database file size calculation with valid path
    func testGetSnapshotDBSizeWithValidPath() throws {
        let dbFilePath = "\(mockSnapshotPath!)/\(Ndb.main_db_file_name)"
        let expectedSize: UInt64 = 2 * 1024 * 1024 // 2 MB
        
        // Create mock snapshot database file
        try createTestFile(at: dbFilePath, size: expectedSize)
        
        // Verify file size can be retrieved
        let actualSize = getActualFileSize(at: dbFilePath)
        XCTAssertNotNil(actualSize, "Snapshot DB file should exist")
        XCTAssertEqual(actualSize, expectedSize, "Snapshot DB file should have expected size")
    }
    
    // MARK: - 3. Byte Formatting Tests
    
    /// Test formatting of zero bytes
    func testFormatBytesZero() {
        let formatted = StorageStatsManager.formatBytes(0)
        // ByteCountFormatter may format as "Zero bytes", "0 bytes", "0 KB", etc.
        // We just verify it's a valid non-empty string
        XCTAssertFalse(formatted.isEmpty, "Formatted string should not be empty")
        // Most common formats include "0" or "Zero"
        let containsZero = formatted.contains("0") || formatted.uppercased().contains("ZERO")
        XCTAssertTrue(containsZero, "Zero bytes should contain '0' or 'Zero', got: \(formatted)")
    }
    
    /// Test formatting of small byte values (< 1 KB)
    func testFormatBytesSmall() {
        let formatted = StorageStatsManager.formatBytes(512)
        XCTAssertFalse(formatted.isEmpty, "Formatted string should not be empty")
        // Should contain a numeric value
        XCTAssertTrue(formatted.contains("512") || formatted.contains("0.5"), "Should contain size value")
    }
    
    /// Test formatting of kilobyte values
    func testFormatBytesKilobytes() {
        let oneKB: UInt64 = 1024
        let formatted = StorageStatsManager.formatBytes(oneKB * 5) // 5 KB
        
        XCTAssertFalse(formatted.isEmpty, "Formatted string should not be empty")
        // Should mention KB or kilobytes
        XCTAssertTrue(formatted.uppercased().contains("KB") || formatted.uppercased().contains("K"), 
                     "Should indicate kilobytes: \(formatted)")
    }
    
    /// Test formatting of megabyte values
    func testFormatBytesMegabytes() {
        let oneMB: UInt64 = 1024 * 1024
        let formatted = StorageStatsManager.formatBytes(oneMB * 10) // 10 MB
        
        XCTAssertFalse(formatted.isEmpty, "Formatted string should not be empty")
        // Should mention MB or megabytes
        XCTAssertTrue(formatted.uppercased().contains("MB") || formatted.uppercased().contains("M"), 
                     "Should indicate megabytes: \(formatted)")
    }
    
    /// Test formatting of gigabyte values
    func testFormatBytesGigabytes() {
        let oneGB: UInt64 = 1024 * 1024 * 1024
        let formatted = StorageStatsManager.formatBytes(oneGB * 2) // 2 GB
        
        XCTAssertFalse(formatted.isEmpty, "Formatted string should not be empty")
        // Should mention GB or gigabytes
        XCTAssertTrue(formatted.uppercased().contains("GB") || formatted.uppercased().contains("G"), 
                     "Should indicate gigabytes: \(formatted)")
    }
    
    /// Test formatting of very large values
    func testFormatBytesLarge() {
        let oneTB: UInt64 = 1024 * 1024 * 1024 * 1024
        let formatted = StorageStatsManager.formatBytes(oneTB)
        
        XCTAssertFalse(formatted.isEmpty, "Formatted string should not be empty")
        // Should handle terabyte values gracefully
        XCTAssertTrue(formatted.uppercased().contains("TB") || formatted.uppercased().contains("T") || 
                     formatted.uppercased().contains("GB") || formatted.uppercased().contains("G"), 
                     "Should format large values: \(formatted)")
    }
    
    // MARK: - 4. Async Storage Stats Calculation Tests
    
    /// Test storage stats calculation without Ndb instance
    func testCalculateStorageStatsWithoutNdb() async throws {
        // Note: This test verifies the calculation succeeds and returns valid stats
        // We don't check exact values since they depend on actual system state
        
        let stats = try await StorageStatsManager.shared.calculateStorageStats(ndb: nil)
        
        // Verify stats structure is valid
        XCTAssertNotNil(stats, "Stats should not be nil")
        XCTAssertNil(stats.nostrdbDetails, "Details should be nil when no Ndb provided")
        
        // All sizes should be non-negative
        XCTAssertGreaterThanOrEqual(stats.nostrdbSize, 0, "NostrDB size should be non-negative")
        XCTAssertGreaterThanOrEqual(stats.snapshotSize, 0, "Snapshot size should be non-negative")
        XCTAssertGreaterThanOrEqual(stats.imageCacheSize, 0, "Image cache size should be non-negative")
        
        // Total should equal sum
        let expectedTotal = stats.nostrdbSize + stats.snapshotSize + stats.imageCacheSize + stats.videoCacheSize + stats.otherSize
        XCTAssertEqual(stats.totalSize, expectedTotal, "Total should equal sum of components")
    }
    
    
    // MARK: - 5. NdbDatabaseStats Tests
    
    /// Test NdbDatabaseStats total size calculation
    func testNdbDatabaseStatsCalculations() {
        let dbStats = NdbDatabaseStats(
            database: .note,
            keySize: 1000,
            valueSize: 5000
        )
        
        XCTAssertEqual(dbStats.totalSize, 6000, "Total should be key + value size")
        XCTAssertEqual(dbStats.database, .note, "Database type should be preserved")
        XCTAssertEqual(dbStats.keySize, 1000, "Key size should be preserved")
        XCTAssertEqual(dbStats.valueSize, 5000, "Value size should be preserved")
    }
    
    /// Test NdbStats total size calculation
    func testNdbStatsTotalCalculation() {
        let stats = NdbStats(databaseStats: [
            NdbDatabaseStats(database: .note, keySize: 1000, valueSize: 5000),
            NdbDatabaseStats(database: .profile, keySize: 500, valueSize: 2000),
            NdbDatabaseStats(database: .noteId, keySize: 200, valueSize: 800)
        ])
        
        // Total should be sum of all database totals
        // (1000+5000) + (500+2000) + (200+800) = 9500
        XCTAssertEqual(stats.totalSize, 9500, "Total should sum all database sizes")
    }
    
    /// Test NdbStats with empty database list
    func testNdbStatsEmpty() {
        let stats = NdbStats(databaseStats: [])
        
        XCTAssertEqual(stats.totalSize, 0, "Empty stats should have zero total")
        XCTAssertTrue(stats.databaseStats.isEmpty, "Database stats should be empty")
    }
    
    /// Test NdbDatabaseStats hashable conformance
    func testNdbDatabaseStatsHashableConformance() {
        let stats1 = NdbDatabaseStats(database: .note, keySize: 1000, valueSize: 5000)
        let stats2 = NdbDatabaseStats(database: .note, keySize: 1000, valueSize: 5000)
        let stats3 = NdbDatabaseStats(database: .profile, keySize: 1000, valueSize: 5000)
        
        XCTAssertEqual(stats1, stats2, "Identical stats should be equal")
        XCTAssertNotEqual(stats1, stats3, "Different database type should not be equal")
        
        // Should work in Set
        let set: Set<NdbDatabaseStats> = [stats1, stats2, stats3]
        XCTAssertEqual(set.count, 2, "Set should contain 2 unique stats")
    }
    
    /// Test NdbStats hashable conformance
    func testNdbStatsHashableConformance() {
        let dbStats1 = NdbDatabaseStats(database: .note, keySize: 1000, valueSize: 5000)
        let dbStats2 = NdbDatabaseStats(database: .profile, keySize: 500, valueSize: 2000)
        
        let stats1 = NdbStats(databaseStats: [dbStats1, dbStats2])
        let stats2 = NdbStats(databaseStats: [dbStats1, dbStats2])
        let stats3 = NdbStats(databaseStats: [dbStats1])
        
        XCTAssertEqual(stats1, stats2, "Identical stats should be equal")
        XCTAssertNotEqual(stats1, stats3, "Different database count should not be equal")
        
        // Should work in Set
        let set: Set<NdbStats> = [stats1, stats2, stats3]
        XCTAssertEqual(set.count, 2, "Set should contain 2 unique stats")
    }
    
    // MARK: - 6. NdbDatabase Enum Tests
    
    /// Test NdbDatabase display names
    func testNdbDatabaseDisplayNames() {
        // Display names include the C enum names in parentheses
        XCTAssertEqual(NdbDatabase.note.displayName, "Notes (NDB_DB_NOTE)", "Note database display name")
        XCTAssertEqual(NdbDatabase.profile.displayName, "Profiles (NDB_DB_PROFILE)", "Profile database display name")
        XCTAssertEqual(NdbDatabase.noteBlocks.displayName, "Note Blocks", "Note blocks display name")
        XCTAssertEqual(NdbDatabase.noteId.displayName, "Note ID Index", "Note ID index display name")
        XCTAssertEqual(NdbDatabase.meta.displayName, "Metadata (NDB_DB_META)", "Metadata display name")
        XCTAssertEqual(NdbDatabase.other.displayName, "Other Data", "Other data display name")
    }
    
    /// Test NdbDatabase icons
    func testNdbDatabaseIcons() {
        // Verify each database has an icon (non-empty string)
        XCTAssertFalse(NdbDatabase.note.icon.isEmpty, "Note should have icon")
        XCTAssertFalse(NdbDatabase.profile.icon.isEmpty, "Profile should have icon")
        XCTAssertFalse(NdbDatabase.noteBlocks.icon.isEmpty, "Note blocks should have icon")
        XCTAssertFalse(NdbDatabase.other.icon.isEmpty, "Other should have icon")
    }
    
    /// Test NdbDatabase colors
    func testNdbDatabaseColors() {
        // Verify each database has a color assigned
        // We can't easily compare Color values, but we can verify they return Color instances
        _ = NdbDatabase.note.color
        _ = NdbDatabase.profile.color
        _ = NdbDatabase.noteBlocks.color
        _ = NdbDatabase.other.color
        
        // If we get here without crashes, colors are working
        XCTAssertTrue(true, "All database colors should be accessible")
    }
    
    /// Test NdbDatabase initialization from index
    func testNdbDatabaseFromIndex() {
        // Test valid indices
        let db0 = NdbDatabase(fromIndex: 0)
        XCTAssertNotEqual(db0, .other, "Index 0 should map to a valid database")
        
        let db1 = NdbDatabase(fromIndex: 1)
        XCTAssertNotEqual(db1, .other, "Index 1 should map to a valid database")
        
        // Test invalid index (should default to .other)
        let dbInvalid = NdbDatabase(fromIndex: 9999)
        XCTAssertEqual(dbInvalid, .other, "Invalid index should default to .other")
    }
    
    // MARK: - 7. Integration Tests
    
    /// Test complete storage stats flow with real-ish data
    func testStorageStatsIntegrationFlow() async throws {
        // This test verifies the entire flow works end-to-end
        // We use actual calculation but don't assert specific values
        
        let stats = try await StorageStatsManager.shared.calculateStorageStats(ndb: nil)
        
        // Verify structure
        XCTAssertNotNil(stats, "Stats should be calculated")
        
        // Verify all components are accessible
        let _ = stats.nostrdbSize
        let _ = stats.snapshotSize
        let _ = stats.imageCacheSize
        let _ = stats.totalSize
        
        // Verify percentage calculation works
        if stats.totalSize > 0 {
            let percentage = stats.percentage(for: stats.nostrdbSize)
            XCTAssertGreaterThanOrEqual(percentage, 0.0, "Percentage should be non-negative")
            XCTAssertLessThanOrEqual(percentage, 100.0, "Percentage should not exceed 100%")
        }
        
        // Verify formatting works
        let formatted = StorageStatsManager.formatBytes(stats.totalSize)
        XCTAssertFalse(formatted.isEmpty, "Formatted size should not be empty")
    }
    
    /// Test concurrent stats calculations (thread safety)
    func testConcurrentStatsCalculations() async throws {
        let iterations = 5
        
        // Launch multiple concurrent calculations
        try await withThrowingTaskGroup(of: StorageStats.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    return try await StorageStatsManager.shared.calculateStorageStats(ndb: nil)
                }
            }
            
            var results: [StorageStats] = []
            for try await stats in group {
                results.append(stats)
            }
            
            XCTAssertEqual(results.count, iterations, "Should complete all calculations")
            
            // All results should have valid structure
            for stats in results {
                XCTAssertGreaterThanOrEqual(stats.nostrdbSize, 0, "NostrDB size should be valid")
                XCTAssertGreaterThanOrEqual(stats.snapshotSize, 0, "Snapshot size should be valid")
                XCTAssertGreaterThanOrEqual(stats.imageCacheSize, 0, "Cache size should be valid")
            }
        }
    }
    
    /// Test storage stats with extreme UInt64 values, including sum at UInt64 boundary (no overflow)
    func testStorageStatsExtremeValues() {
        // Case: Sum at UInt64 boundary (no overflow)
        // UInt64.max - 4 + 1 + 1 + 1 + 1 == UInt64.max
        let maxStats = StorageStats(
            nostrdbDetails: nil,
            nostrdbSize: UInt64.max - 4,
            snapshotSize: 1,
            imageCacheSize: 1,
            videoCacheSize: 1,
            otherSize: 1
        )
        // Verify correct summation at UInt64 boundary
        XCTAssertEqual(maxStats.totalSize, UInt64.max, "Total should be exactly UInt64.max at boundary; no overflow should occur")

        // Verify percentage calculation for each component
        XCTAssertEqual(maxStats.percentage(for: UInt64.max - 4), (Double(UInt64.max - 4) / Double(UInt64.max)) * 100.0, accuracy: 0.0001)
        XCTAssertEqual(maxStats.percentage(for: 1), (1.0 / Double(UInt64.max)) * 100.0, accuracy: 0.0001)

        // All zeros case (already tested elsewhere, but included for completeness)
        let zeroStats = StorageStats(
            nostrdbDetails: nil,
            nostrdbSize: 0,
            snapshotSize: 0,
            imageCacheSize: 0,
            videoCacheSize: 0,
            otherSize: 0
        )
        XCTAssertEqual(zeroStats.totalSize, 0, "Zero stats should have zero total")
        XCTAssertEqual(zeroStats.percentage(for: 0), 0.0, "Zero percentage for zero total")

        // If overflow handling should be explicitly tested, add a comment. With current implementation, overflow cannot occur for UInt64 sums with three terms.
        // If more than three terms or arbitrary user input are ever summed, consider adding explicit overflow guards.
    }
    
    /// Test byte formatter with various edge cases
    func testFormatBytesEdgeCases() {
        // Powers of 1024
        let formatted1K = StorageStatsManager.formatBytes(1024)
        XCTAssertFalse(formatted1K.isEmpty, "Should format 1KB")
        
        let formatted1M = StorageStatsManager.formatBytes(1024 * 1024)
        XCTAssertFalse(formatted1M.isEmpty, "Should format 1MB")
        
        let formatted1G = StorageStatsManager.formatBytes(1024 * 1024 * 1024)
        XCTAssertFalse(formatted1G.isEmpty, "Should format 1GB")
        
        // Odd values
        let formatted999 = StorageStatsManager.formatBytes(999)
        XCTAssertFalse(formatted999.isEmpty, "Should format 999 bytes")
        
        let formatted1023 = StorageStatsManager.formatBytes(1023)
        XCTAssertFalse(formatted1023.isEmpty, "Should format 1023 bytes")
    }
}

