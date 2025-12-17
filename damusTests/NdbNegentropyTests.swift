//
//  NdbNegentropyTests.swift
//  damusTests
//
//  Tests for native nostrdb negentropy integration.
//  These tests verify the Swift bindings for ndb_negentropy work correctly.
//

import XCTest
@testable import damus

final class NdbNegentropyTests: XCTestCase {

    // MARK: - Storage Tests

    func testStorageInitialization() throws {
        // Storage should initialize successfully
        let storage = try NdbNegentropyStorage()
        XCTAssertNotNil(storage)
        XCTAssertEqual(storage.count, 0)
        XCTAssertFalse(storage.isSealed)
    }

    func testStorageAddItems() throws {
        let storage = try NdbNegentropyStorage()

        // Create test event IDs (32 bytes each)
        let id1 = Data(repeating: 0x01, count: 32)
        let id2 = Data(repeating: 0x02, count: 32)
        let id3 = Data(repeating: 0x03, count: 32)

        // Add items with different timestamps
        try storage.add(timestamp: 1000, id: id1)
        try storage.add(timestamp: 2000, id: id2)
        try storage.add(timestamp: 3000, id: id3)

        XCTAssertEqual(storage.count, 3)
        XCTAssertFalse(storage.isSealed)
    }

    func testStorageSeal() throws {
        let storage = try NdbNegentropyStorage()

        let id1 = Data(repeating: 0xAA, count: 32)
        try storage.add(timestamp: 1000, id: id1)

        // Seal should succeed
        try storage.seal()
        XCTAssertTrue(storage.isSealed)

        // Adding after seal should fail
        let id2 = Data(repeating: 0xBB, count: 32)
        XCTAssertThrowsError(try storage.add(timestamp: 2000, id: id2)) { error in
            XCTAssertEqual(error as? NdbNegentropyError, .storageAlreadySealed)
        }
    }

    func testStorageWithNoteId() throws {
        let storage = try NdbNegentropyStorage()

        // Use a real hex ID
        let hexId = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        guard let noteId = NoteId(hex: hexId) else {
            XCTFail("Failed to create NoteId from hex")
            return
        }

        try storage.add(timestamp: 1000, noteId: noteId)
        XCTAssertEqual(storage.count, 1)
    }

    // MARK: - Reconciliation Tests

    func testNegentropyInitialization() throws {
        let storage = try NdbNegentropyStorage()

        // Add some items
        let id1 = Data(repeating: 0x01, count: 32)
        let id2 = Data(repeating: 0x02, count: 32)
        try storage.add(timestamp: 1000, id: id1)
        try storage.add(timestamp: 2000, id: id2)
        try storage.seal()

        // Negentropy should initialize with sealed storage
        let negentropy = try NdbNegentropy(storage: storage)
        XCTAssertNotNil(negentropy)
        XCTAssertFalse(negentropy.isComplete)
    }

    func testNegentropyInitialMessage() throws {
        let storage = try NdbNegentropyStorage()

        let id1 = Data(repeating: 0x01, count: 32)
        try storage.add(timestamp: 1000, id: id1)
        try storage.seal()

        let negentropy = try NdbNegentropy(storage: storage)

        // Initial message should be valid hex
        let initialHex = try negentropy.initiateHex()
        XCTAssertFalse(initialHex.isEmpty)

        // Should start with protocol version 0x61 (hex "61")
        XCTAssertTrue(initialHex.hasPrefix("61"))

        // Should be valid hex (even length, only hex characters)
        XCTAssertEqual(initialHex.count % 2, 0)
        XCTAssertTrue(initialHex.allSatisfy { $0.isHexDigit })
    }

    func testNegentropyEmptyStorage() throws {
        let storage = try NdbNegentropyStorage()
        try storage.seal()

        let negentropy = try NdbNegentropy(storage: storage)

        // Should still be able to initiate with empty storage
        let initialHex = try negentropy.initiateHex()
        XCTAssertFalse(initialHex.isEmpty)
        XCTAssertTrue(initialHex.hasPrefix("61"))
    }

    func testNegentropyHaveAndNeedIds() throws {
        let storage = try NdbNegentropyStorage()
        try storage.seal()

        let negentropy = try NdbNegentropy(storage: storage)
        _ = try negentropy.initiateHex()

        // Initially no have/need IDs
        XCTAssertTrue(negentropy.haveIds.isEmpty)
        XCTAssertTrue(negentropy.needIds.isEmpty)
    }

    func testNegentropyConfig() throws {
        let storage = try NdbNegentropyStorage()
        try storage.seal()

        // Test with custom config
        let config = NdbNegentropyConfig(
            frameSizeLimit: 4096,
            idlistThreshold: 8,
            splitCount: 8
        )

        let negentropy = try NdbNegentropy(storage: storage, config: config)
        XCTAssertNotNil(negentropy)

        let initialHex = try negentropy.initiateHex()
        XCTAssertFalse(initialHex.isEmpty)
    }

    // MARK: - Protocol Compliance Tests

    func testProtocolVersion() throws {
        let storage = try NdbNegentropyStorage()
        try storage.seal()

        let negentropy = try NdbNegentropy(storage: storage)
        let initialData = try negentropy.initiate()

        // First byte should be protocol version 0x61
        XCTAssertEqual(initialData.first, 0x61)
    }

    func testReconcileWithInvalidMessage() throws {
        let storage = try NdbNegentropyStorage()
        try storage.seal()

        let negentropy = try NdbNegentropy(storage: storage)
        _ = try negentropy.initiateHex()

        // Invalid hex should throw
        XCTAssertThrowsError(try negentropy.reconcileHex(hexMessage: "not-valid-hex"))

        // Wrong protocol version should throw
        XCTAssertThrowsError(try negentropy.reconcileHex(hexMessage: "62"))
    }

    func testReconcileWithVersionOnlyResponse() throws {
        let storage = try NdbNegentropyStorage()
        try storage.seal()

        let negentropy = try NdbNegentropy(storage: storage)
        _ = try negentropy.initiateHex()

        // A response with just version byte (0x61) indicates sync complete
        // This simulates what a relay sends when it has no differences
        let response = try negentropy.reconcileHex(hexMessage: "61")

        // Empty response means reconciliation is complete
        XCTAssertTrue(response.isEmpty || negentropy.isComplete)
    }

    // MARK: - Memory Management Tests

    func testStorageDeallocation() throws {
        // This test ensures storage is properly deallocated
        weak var weakStorage: NdbNegentropyStorage?

        autoreleasepool {
            let storage = try! NdbNegentropyStorage()
            try! storage.add(timestamp: 1000, id: Data(repeating: 0x01, count: 32))
            try! storage.seal()
            weakStorage = storage
        }

        // Storage should be deallocated
        XCTAssertNil(weakStorage)
    }

    func testNegentropyKeepsStorageAlive() throws {
        // Negentropy should keep storage alive while in use
        weak var weakStorage: NdbNegentropyStorage?
        var negentropy: NdbNegentropy?

        autoreleasepool {
            let storage = try! NdbNegentropyStorage()
            try! storage.seal()
            weakStorage = storage
            negentropy = try! NdbNegentropy(storage: storage)
        }

        // Storage should still be alive because negentropy holds reference
        XCTAssertNotNil(weakStorage)
        XCTAssertNotNil(negentropy)

        // After releasing negentropy, storage should be deallocated
        negentropy = nil
        XCTAssertNil(weakStorage)
    }
}
