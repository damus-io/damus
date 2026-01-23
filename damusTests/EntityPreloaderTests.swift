//
//  EntityPreloaderTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-01-22.
//

import XCTest
import NostrSDK
import Negentropy
@testable import damus

/// Tests for the EntityPreloader functionality.
///
/// These tests verify that EntityPreloader correctly:
/// - Extracts author and referenced pubkeys from notes
/// - Batches preload requests efficiently
/// - Uses standard Nostr subscriptions to fetch metadata
/// - Integrates properly with SubscriptionManager
final class EntityPreloaderTests: XCTestCase {
    
    // MARK: - Helper Functions
    
    /// Creates and runs a local relay on the specified port.
    /// - Parameter port: The port number to run the relay on
    /// - Returns: The running LocalRelay instance
    private func setupRelay(port: UInt16) async throws -> LocalRelay {
        let builder = RelayBuilder().port(port: port).rateLimit(limit: .init(maxReqs: 100, notesPerMinute: 100))
        let relay = LocalRelay(builder: builder)
        try await relay.run()
        print("Relay url: \(await relay.url())")
        return relay
    }
    
    /// Connects to a relay and waits for the connection to be established.
    /// - Parameters:
    ///   - url: The relay URL to connect to
    ///   - label: Optional label for logging (e.g., "Relay1", "Relay2")
    /// - Returns: The connected RelayConnection instance
    private func connectToRelay(url: RelayURL, label: String = "") async -> RelayConnection {
        var connectionContinuation: CheckedContinuation<Void, Never>?
        var timeoutTask: Task<Void, Never>?
        var isResumed = false
        
        let relayConnection = RelayConnection(url: url, handleEvent: { _ in }, processUnverifiedWSEvent: { wsEvent in
            let prefix = label.isEmpty ? "" : "(\(label)) "
            switch wsEvent {
            case .connected:
                if !isResumed {
                    isResumed = true
                    timeoutTask?.cancel()
                    connectionContinuation?.resume()
                }
            case .message(let message):
                print("ENTITY_PRELOADER_TEST \(prefix): Received: \(message)")
            case .disconnected(let closeCode, let string):
                print("ENTITY_PRELOADER_TEST \(prefix): Disconnected: \(closeCode); \(String(describing: string))")
            case .error(let error):
                print("ENTITY_PRELOADER_TEST \(prefix): Received error: \(error)")
            }
        })
        relayConnection.connect()
        
        // Wait for connection to be established with timeout
        await withCheckedContinuation { continuation in
            connectionContinuation = continuation
            
            // Start timeout task
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                if !isResumed {
                    isResumed = true
                    print("ENTITY_PRELOADER_TEST \(label.isEmpty ? "" : "(\(label)) ")ERROR: Connection timeout after 30 seconds")
                    continuation.resume()
                    XCTFail("Connection to relay \(url) timed out after 30 seconds")
                }
            }
        }
        
        return relayConnection
    }
    
    /// Sends events to a relay connection.
    /// - Parameters:
    ///   - events: Array of NostrEvent to send
    ///   - connection: The RelayConnection to send events through
    private func sendEvents(_ events: [NostrEvent], to connection: RelayConnection) async throws {
        for event in events {
            connection.send(.typical(.event(event)))
        }
    }
    
    /// Sets up a NostrNetworkManager with the specified relay URLs.
    /// - Parameters:
    ///   - urls: Array of RelayURL to add to the manager
    ///   - ndb: The Ndb instance to use
    /// - Returns: Configured and connected NostrNetworkManager
    private func setupNetworkManager(with urls: [RelayURL], ndb: Ndb) async throws -> NostrNetworkManager {
        let delegate = TestNetworkDelegate(ndb: ndb, keypair: test_keypair, bootstrapRelays: urls)
        let networkManager = NostrNetworkManager(delegate: delegate, addNdbToRelayPool: true)
        
        // Manually add relays to the pool since we're bypassing normal initialization
        for url in urls {
            do {
                try await networkManager.userRelayList.insert(relay: .init(url: url, rwConfiguration: .readWrite), force: true)
            }
            catch {
                switch error {
                case .relayAlreadyExists: continue
                default: throw error
                }
            }
        }
        
        await networkManager.connect()
        // Wait for relay pool to be ready.
        try await Task.sleep(for: .seconds(2))
        
        return networkManager
    }
    
    /// Stores events in NostrDB for testing purposes.
    /// - Parameters:
    ///   - events: Array of NostrEvent to store in NDB
    ///   - ndb: The Ndb instance to store events in
    private func storeEventsInNdb(_ events: [NostrEvent], ndb: Ndb) {
        for event in events {
            do {
                try ndb.add(event: event)
            } catch {
                XCTFail("Failed to store event in NDB: \(error)")
            }
        }
    }
    
    /// Creates a test note with the specified content and referenced pubkeys.
    /// - Parameters:
    ///   - content: The content of the note
    ///   - keypair: The keypair to sign the note with
    ///   - referencedPubkeys: Pubkeys to add as p-tags
    /// - Returns: A NostrEvent with the specified references
    private func createNoteWithReferences(content: String, keypair: Keypair, referencedPubkeys: [Pubkey] = []) -> NostrEvent? {
        var tags: [[String]] = []
        for pubkey in referencedPubkeys {
            tags.append(["p", pubkey.hex()])
        }
        
        return NostrEvent(content: content, keypair: keypair, tags: tags)
    }
    
    /// Creates a metadata event for a given pubkey.
    /// - Parameters:
    ///   - keypair: The keypair for the profile
    ///   - displayName: Display name for the profile
    /// - Returns: A metadata NostrEvent
    private func createMetadataEvent(keypair: Keypair, displayName: String) -> NostrEvent? {
        let metadata = """
        {
            "name": "\(displayName)",
            "display_name": "\(displayName)",
            "about": "Test user"
        }
        """
        return NostrEvent(content: metadata, keypair: keypair, kind: 0)
    }
    
    // MARK: - Test Cases
    
    /// Test that preloading with .noPreloading strategy does not trigger metadata fetching
    func testNoPreloadingStrategy() async throws {
        // Given: A relay with a note and metadata for the author
        let relay = try await setupRelay(port: 9100)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let authorKeypair = generate_new_keypair().to_keypair()
        let note = NostrEvent(content: "Test note", keypair: authorKeypair)!
        let metadata = createMetadataEvent(keypair: authorKeypair, displayName: "Test Author")!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        try await sendEvents([note, metadata], to: relayConnection)
        
        let ndb = await generate_test_damus_state(mock_profile_info: nil).ndb
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let receivedNote = XCTestExpectation(description: "Received note")
        
        // When: Streaming with .noPreloading strategy
        Task {
            var noteReceived = false
            for await _ in networkManager.reader.streamIndefinitely(
                filters: [NostrFilter(kinds: [.text])],
                streamMode: .ndbAndNetworkParallel(networkOptimization: nil),
                preloadStrategy: .noPreloading
            ) {
                if !noteReceived {
                    noteReceived = true
                    receivedNote.fulfill()
                }
            }
        }
        
        // Then: Should receive the note but metadata should not be in NDB
        await fulfillment(of: [receivedNote], timeout: 5.0)
        
        // Give a moment to see if any preloading happens (it shouldn't)
        try await Task.sleep(for: .seconds(2))
        
        // Verify metadata was NOT preloaded into NDB
        let hasMetadata = (try? ndb.lookup_profile(authorKeypair.pubkey, borrow: { pr in
            pr != nil
        })) ?? false
        XCTAssertFalse(hasMetadata, "Metadata should not be preloaded with .noPreloading strategy")
    }
    
    /// Test that preloading with .preload strategy fetches author metadata
    func testPreloadAuthorMetadata() async throws {
        // Given: A relay with a note and metadata for the author (metadata NOT in NDB)
        let relay = try await setupRelay(port: 9101)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let authorKeypair = test_keypair
        let note = NostrEvent(content: "Test note", keypair: authorKeypair)!
        let metadata = createMetadataEvent(keypair: authorKeypair, displayName: "Test Author")!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        try await sendEvents([note, metadata], to: relayConnection)
        
        let damus_state = await generate_test_damus_state(mock_profile_info: [:])
        
        let ndb = damus_state.ndb
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let receivedNote = XCTestExpectation(description: "Received note")
        let metadataPreloaded = XCTestExpectation(description: "Metadata preloaded")
        
        // When: Streaming with .preload strategy
        Task {
            var noteReceived = false
            for await _ in networkManager.reader.streamIndefinitely(
                filters: [NostrFilter(kinds: [.text])],
                streamMode: .ndbAndNetworkParallel(networkOptimization: nil),
                preloadStrategy: .preload
            ) {
                if !noteReceived {
                    noteReceived = true
                    receivedNote.fulfill()
                    
                    // Poll for metadata to be preloaded
                    for _ in 0..<20 {
                        try? await Task.sleep(for: .milliseconds(100))
                        if (try? ndb.lookup_profile(authorKeypair.pubkey, borrow: { pr in pr != nil })) ?? false {
                            metadataPreloaded.fulfill()
                            break
                        }
                    }
                }
            }
        }
        
        // Then: Should receive the note and metadata should be preloaded
        await fulfillment(of: [receivedNote, metadataPreloaded], timeout: 30.0)
    }
    
    /// Test that preloading fetches metadata for all referenced pubkeys (p-tags)
    func testPreloadReferencedPubkeys() async throws {
        // Given: A relay with a note that references other users, and metadata for all referenced users
        let relay = try await setupRelay(port: 9102)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let authorKeypair = test_keypair
        let user1Keypair = generate_new_keypair().to_keypair()
        let user2Keypair = generate_new_keypair().to_keypair()
        
        let note = createNoteWithReferences(
            content: "Mentioning users",
            keypair: authorKeypair,
            referencedPubkeys: [user1Keypair.pubkey, user2Keypair.pubkey]
        )!
        
        let authorMetadata = createMetadataEvent(keypair: authorKeypair, displayName: "Author")!
        let user1Metadata = createMetadataEvent(keypair: user1Keypair, displayName: "User 1")!
        let user2Metadata = createMetadataEvent(keypair: user2Keypair, displayName: "User 2")!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        try await sendEvents([note, authorMetadata, user1Metadata, user2Metadata], to: relayConnection)
        
        let ndb = await generate_test_damus_state(mock_profile_info: nil).ndb
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let receivedNote = XCTestExpectation(description: "Received note")
        let authorMetadataPreloaded = XCTestExpectation(description: "Author metadata preloaded")
        let user1MetadataPreloaded = XCTestExpectation(description: "User 1 metadata preloaded")
        let user2MetadataPreloaded = XCTestExpectation(description: "User 2 metadata preloaded")
        
        // When: Streaming with .preload strategy
        Task {
            var noteReceived = false
            for await _ in networkManager.reader.streamIndefinitely(
                filters: [NostrFilter(kinds: [.text])],
                streamMode: .ndbAndNetworkParallel(networkOptimization: nil),
                preloadStrategy: .preload
            ) {
                if !noteReceived {
                    noteReceived = true
                    receivedNote.fulfill()
                    
                    // Poll for all metadata to be preloaded
                    for _ in 0..<30 {
                        try? await Task.sleep(for: .milliseconds(200))
                        
                        var allPreloaded = true
                        
                        if !((try? ndb.lookup_profile(authorKeypair.pubkey, borrow: { pr in pr != nil })) ?? false) {
                            allPreloaded = false
                        } else if !authorMetadataPreloaded.isInverted {
                            authorMetadataPreloaded.fulfill()
                        }
                        
                        if !((try? ndb.lookup_profile(user1Keypair.pubkey, borrow: { pr in pr != nil })) ?? false) {
                            allPreloaded = false
                        } else if !user1MetadataPreloaded.isInverted {
                            user1MetadataPreloaded.fulfill()
                        }
                        
                        if !((try? ndb.lookup_profile(user2Keypair.pubkey, borrow: { pr in pr != nil })) ?? false) {
                            allPreloaded = false
                        } else if !user2MetadataPreloaded.isInverted {
                            user2MetadataPreloaded.fulfill()
                        }
                        
                        if allPreloaded {
                            break
                        }
                    }
                }
            }
        }
        
        // Then: Should preload metadata for author and all referenced users
        await fulfillment(of: [receivedNote, authorMetadataPreloaded, user1MetadataPreloaded, user2MetadataPreloaded], timeout: 30.0)
    }
    
    /// Test that preloading batches requests efficiently when multiple notes arrive
    func testBatchingMultipleNotes() async throws {
        // Given: A relay with multiple notes from different authors and their metadata
        let relay = try await setupRelay(port: 9103)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let author1Keypair = test_keypair
        let author2Keypair = generate_new_keypair().to_keypair()
        let author3Keypair = generate_new_keypair().to_keypair()
        
        let note1 = NostrEvent(content: "Note 1", keypair: author1Keypair)!
        let note2 = NostrEvent(content: "Note 2", keypair: author2Keypair)!
        let note3 = NostrEvent(content: "Note 3", keypair: author3Keypair)!
        
        let metadata1 = createMetadataEvent(keypair: author1Keypair, displayName: "Author 1")!
        let metadata2 = createMetadataEvent(keypair: author2Keypair, displayName: "Author 2")!
        let metadata3 = createMetadataEvent(keypair: author3Keypair, displayName: "Author 3")!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        try await sendEvents([note1, note2, note3, metadata1, metadata2, metadata3], to: relayConnection)
        
        let ndb = await generate_test_damus_state(mock_profile_info: nil).ndb
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let receivedAllNotes = XCTestExpectation(description: "Received all notes")
        receivedAllNotes.expectedFulfillmentCount = 3
        
        let allMetadataPreloaded = XCTestExpectation(description: "All metadata preloaded")
        
        // When: Streaming multiple notes with .preload strategy
        Task {
            var notesReceived = 0
            for await _ in networkManager.reader.streamIndefinitely(
                filters: [NostrFilter(kinds: [.text])],
                streamMode: .ndbAndNetworkParallel(networkOptimization: nil),
                preloadStrategy: .preload
            ) {
                notesReceived += 1
                receivedAllNotes.fulfill()
                
                if notesReceived >= 3 {
                    print("🔍 All 3 notes received, polling for metadata preload...")
                    print("📝 Author 1 pubkey: \(author1Keypair.pubkey.hex())")
                    print("📝 Author 2 pubkey: \(author2Keypair.pubkey.hex())")
                    print("📝 Author 3 pubkey: \(author3Keypair.pubkey.hex())")
                    
                    // Poll for all metadata to be preloaded
                    // EntityPreloader batches after 1 second, plus time for negentropy sync
                    for iteration in 0..<60 {
                        try? await Task.sleep(for: .milliseconds(500))
                        
                        let hasAuthor1 = (try? ndb.lookup_profile(author1Keypair.pubkey, borrow: { pr in pr != nil })) ?? false
                        let hasAuthor2 = (try? ndb.lookup_profile(author2Keypair.pubkey, borrow: { pr in pr != nil })) ?? false
                        let hasAuthor3 = (try? ndb.lookup_profile(author3Keypair.pubkey, borrow: { pr in pr != nil })) ?? false
                        
                        if iteration % 4 == 0 {  // Log every 2 seconds
                            print("⏱️  Iteration \(iteration): Author1=\(hasAuthor1), Author2=\(hasAuthor2), Author3=\(hasAuthor3)")
                        }
                        
                        let hasAll = hasAuthor1 && hasAuthor2 && hasAuthor3
                        
                        if hasAll {
                            print("✅ All metadata preloaded!")
                            allMetadataPreloaded.fulfill()
                            break
                        }
                    }
                    
                    // Final check
                    let finalAuthor1 = (try? ndb.lookup_profile(author1Keypair.pubkey, borrow: { pr in pr != nil })) ?? false
                    let finalAuthor2 = (try? ndb.lookup_profile(author2Keypair.pubkey, borrow: { pr in pr != nil })) ?? false
                    let finalAuthor3 = (try? ndb.lookup_profile(author3Keypair.pubkey, borrow: { pr in pr != nil })) ?? false
                    print("❌ Final state after timeout: Author1=\(finalAuthor1), Author2=\(finalAuthor2), Author3=\(finalAuthor3)")
                    
                    break
                }
            }
        }
        
        // Then: Should batch and preload all metadata
        await fulfillment(of: [receivedAllNotes, allMetadataPreloaded], timeout: 60.0)
    }
    
    /// Test that preloading works correctly with negentropy streaming mode
    func testPreloadWithNegentropyStreaming() async throws {
        // Given: A relay with a note and metadata, NDB has the note but not the metadata
        let relay = try await setupRelay(port: 9104)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let authorKeypair = test_keypair
        let note = NostrEvent(content: "Test note", keypair: authorKeypair)!
        let metadata = createMetadataEvent(keypair: authorKeypair, displayName: "Test Author")!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        try await sendEvents([note, metadata], to: relayConnection)
        
        let ndb = await generate_test_damus_state(mock_profile_info: nil).ndb
        storeEventsInNdb([note], ndb: ndb)
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let receivedNoteFromNdb = XCTestExpectation(description: "Received note from NDB")
        let metadataPreloaded = XCTestExpectation(description: "Metadata preloaded")
        
        // When: Using negentropy streaming with preload
        Task {
            var noteReceived = false
            for await _ in networkManager.reader.streamIndefinitely(
                filters: [NostrFilter(kinds: [.text])],
                streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy),
                preloadStrategy: .preload
            ) {
                if !noteReceived {
                    noteReceived = true
                    receivedNoteFromNdb.fulfill()
                    
                    // Poll for metadata to be preloaded
                    for _ in 0..<20 {
                        try? await Task.sleep(for: .milliseconds(200))
                        if (try? ndb.lookup_profile(authorKeypair.pubkey, borrow: { pr in pr != nil })) ?? false {
                            metadataPreloaded.fulfill()
                            break
                        }
                    }
                }
            }
        }
        
        // Then: Should receive note from NDB and preload metadata from network
        await fulfillment(of: [receivedNoteFromNdb, metadataPreloaded], timeout: 30.0)
    }
    
    /// Test that preloading doesn't duplicate requests for the same pubkey
    func testPreloadDeduplication() async throws {
        // Given: A relay with multiple notes from the same author and their metadata
        let relay = try await setupRelay(port: 9105)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let authorKeypair = test_keypair
        
        let note1 = NostrEvent(content: "Note 1", keypair: authorKeypair)!
        let note2 = NostrEvent(content: "Note 2", keypair: authorKeypair)!
        let note3 = NostrEvent(content: "Note 3", keypair: authorKeypair)!
        let metadata = createMetadataEvent(keypair: authorKeypair, displayName: "Test Author")!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        try await sendEvents([note1, note2, note3, metadata], to: relayConnection)
        
        let ndb = await generate_test_damus_state(mock_profile_info: nil).ndb
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let receivedAllNotes = XCTestExpectation(description: "Received all notes")
        receivedAllNotes.expectedFulfillmentCount = 3
        
        let metadataPreloaded = XCTestExpectation(description: "Metadata preloaded")
        
        // When: Streaming multiple notes from same author with .preload strategy
        Task {
            var notesReceived = 0
            for await _ in networkManager.reader.streamIndefinitely(
                filters: [NostrFilter(kinds: [.text])],
                streamMode: .ndbAndNetworkParallel(networkOptimization: nil),
                preloadStrategy: .preload
            ) {
                notesReceived += 1
                receivedAllNotes.fulfill()
                
                if notesReceived == 3 {
                    // Poll for metadata to be preloaded
                    for _ in 0..<20 {
                        try? await Task.sleep(for: .milliseconds(200))
                        if (try? ndb.lookup_profile(authorKeypair.pubkey, borrow: { pr in pr != nil })) ?? false {
                            metadataPreloaded.fulfill()
                            break
                        }
                    }
                }
            }
        }
        
        // Then: Should receive all notes and preload metadata once (deduplication happens internally)
        await fulfillment(of: [receivedAllNotes, metadataPreloaded], timeout: 10.0)
        
        // Verify the metadata is in NDB
        let hasProfile = (try? ndb.lookup_profile(authorKeypair.pubkey, borrow: { pr in pr != nil })) ?? false
        XCTAssertTrue(hasProfile, "Metadata should be preloaded")
    }
    
    /// Test preloading with streamExistingEvents (which stops at EOSE)
    func testPreloadWithStreamExistingEvents() async throws {
        // Given: A relay with a note and metadata
        let relay = try await setupRelay(port: 9106)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let authorKeypair = test_keypair
        let note = NostrEvent(content: "Test note", keypair: authorKeypair)!
        let metadata = createMetadataEvent(keypair: authorKeypair, displayName: "Test Author")!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        try await sendEvents([note, metadata], to: relayConnection)
        
        let ndb = await generate_test_damus_state(mock_profile_info: nil).ndb
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let receivedNote = XCTestExpectation(description: "Received note")
        let streamEnded = XCTestExpectation(description: "Stream ended at EOSE")
        let metadataPreloaded = XCTestExpectation(description: "Metadata preloaded")
        
        // When: Using streamExistingEvents with preload
        Task {
            var noteReceived = false
            for await _ in networkManager.reader.streamExistingEvents(
                filters: [NostrFilter(kinds: [.text])],
                streamMode: .ndbAndNetworkParallel(networkOptimization: nil),
                preloadStrategy: .preload
            ) {
                if !noteReceived {
                    noteReceived = true
                    receivedNote.fulfill()
                }
            }
            streamEnded.fulfill()
            
            // Poll for metadata after stream ends
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(200))
                if (try? ndb.lookup_profile(authorKeypair.pubkey, borrow: { pr in pr != nil })) ?? false {
                    metadataPreloaded.fulfill()
                    break
                }
            }
        }
        
        // Then: Should receive note, stream should end, and metadata should be preloaded
        await fulfillment(of: [receivedNote, streamEnded, metadataPreloaded], timeout: 30.0)
    }
    
    // MARK: - Follow Pack Race Condition Tests
    
    /// Creates a follow pack event (kind 39089) with the specified users.
    ///
    /// - Parameters:
    ///   - authorKeypair: The keypair of the follow pack creator
    ///   - title: Title of the follow pack
    ///   - packId: Unique identifier for the pack (d-tag)
    ///   - userPubkeys: Array of pubkeys to include in the pack
    /// - Returns: A NostrEvent representing the follow pack
    private func createFollowPackEvent(
        authorKeypair: Keypair,
        title: String,
        packId: String,
        userPubkeys: [Pubkey]
    ) -> NostrEvent? {
        var tags: [[String]] = [
            ["title", title],
            ["d", packId],
            ["description", "Test follow pack for preloader testing"]
        ]
        for pubkey in userPubkeys {
            tags.append(["p", pubkey.hex()])
        }
        return NostrEvent(
            content: "",
            keypair: authorKeypair,
            kind: NostrKind.follow_list.rawValue,
            tags: tags
        )
    }
    
    /// Test that verifies the race condition: when a follow pack event is received,
    /// the profiles listed in the pack are NOT yet available in NDB immediately after
    /// the event is yielded to the stream consumer.
    ///
    /// This test demonstrates the timing issue where views would render before
    /// profile metadata has been preloaded.
    func testFollowPackProfilesNotAvailableImmediately() async throws {
        // Given: A relay with a follow pack event containing 80 users, and metadata for all users
        let relay = try await setupRelay(port: 9107)
        let relayUrl = RelayURL(await relay.url().description)!
        
        // Create 65 users with their metadata
        let allUserKeypairs = (0..<65).map { _ in generate_new_keypair().to_keypair() }
        
        // Create metadata events for all users
        let metadataEvents = allUserKeypairs.map { keypair in
            createMetadataEvent(keypair: keypair, displayName: "User \(keypair.pubkey.hex().prefix(8))")!
        }
        
        // Create a follow pack event with p-tags for all users
        let packAuthorKeypair = test_keypair
        let followPackEvent = createFollowPackEvent(
            authorKeypair: packAuthorKeypair,
            title: "Test Follow Pack",
            packId: "test-pack-\(UUID().uuidString)",
            userPubkeys: allUserKeypairs.map { $0.pubkey }
        )!
        
        // Also create metadata for the pack author
        let packAuthorMetadata = createMetadataEvent(keypair: packAuthorKeypair, displayName: "Pack Author")!
        
        // Debug: verify the follow pack event has all p-tags
        let pTagCount = Array(followPackEvent.referenced_pubkeys).count
        print("🔍 DEBUG: Follow pack event has \(pTagCount) referenced pubkeys (expected 80)")
        
        // Send all events to the relay
        let relayConnection = await connectToRelay(url: relayUrl)
        print("🔍 DEBUG: Sending \(metadataEvents.count + 2) events to relay (1 follow pack + 1 author metadata + \(metadataEvents.count) user metadata)")
        try await sendEvents([followPackEvent, packAuthorMetadata] + metadataEvents, to: relayConnection)
        
        // Give the relay more time to store all events - 82 events need time to be processed
        try await Task.sleep(for: .seconds(10))
        print("🔍 DEBUG: Waited 3 seconds for relay to store events")
        
        // NDB starts empty (no profiles)
        let ndb = await generate_test_damus_state(mock_profile_info: nil).ndb
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        // Track which profiles were available immediately vs after delay
        var profilesAvailableImmediately: [Pubkey] = []
        var profilesAvailableAfterDelay: [Pubkey] = []
        
        let receivedFollowPack = XCTestExpectation(description: "Received follow pack event")
        let checkedImmediateAvailability = XCTestExpectation(description: "Checked immediate availability")
        let checkedDelayedAvailability = XCTestExpectation(description: "Checked delayed availability")
        
        // When: Streaming follow pack events with .preload strategy
        Task {
            for await lender in networkManager.reader.streamExistingEvents(
                filters: [NostrFilter(kinds: [.follow_list])],
                streamMode: .ndbAndNetworkParallel(networkOptimization: nil),
                preloadStrategy: .preload
            ) {
                receivedFollowPack.fulfill()
                
                // IMMEDIATELY check which profiles are available (simulates view rendering)
                // This is what happens when FollowPackView renders its profile pictures
                for keypair in allUserKeypairs {
                    let hasProfile = (try? ndb.lookup_profile(keypair.pubkey, borrow: { pr in pr != nil })) ?? false
                    if hasProfile {
                        profilesAvailableImmediately.append(keypair.pubkey)
                    }
                }
                checkedImmediateAvailability.fulfill()
                
                print("📊 IMMEDIATE CHECK: \(profilesAvailableImmediately.count)/\(allUserKeypairs.count) profiles available")
                
                // Now wait for preloading to complete (up to 5 seconds)
                // The preloader batches after 1 second, plus time for negentropy sync
                for iteration in 0..<25 {
                    try? await Task.sleep(for: .milliseconds(200))
                    
                    var allLoaded = true
                    for keypair in allUserKeypairs {
                        let hasProfile = (try? ndb.lookup_profile(keypair.pubkey, borrow: { pr in pr != nil })) ?? false
                        if !hasProfile {
                            allLoaded = false
                        }
                    }
                    
                    if iteration % 5 == 0 {
                        var loadedCount = 0
                        for keypair in allUserKeypairs {
                            if (try? ndb.lookup_profile(keypair.pubkey, borrow: { pr in pr != nil })) ?? false {
                                loadedCount += 1
                            }
                        }
                        print("⏱️  Iteration \(iteration): \(loadedCount)/\(allUserKeypairs.count) profiles loaded")
                    }
                    
                    if allLoaded { break }
                }
                
                // Check which profiles are available after the delay
                for keypair in allUserKeypairs {
                    let hasProfile = (try? ndb.lookup_profile(keypair.pubkey, borrow: { pr in pr != nil })) ?? false
                    if hasProfile {
                        profilesAvailableAfterDelay.append(keypair.pubkey)
                    }
                }
                checkedDelayedAvailability.fulfill()
                
                print("📊 DELAYED CHECK: \(profilesAvailableAfterDelay.count)/\(allUserKeypairs.count) profiles available")
                
                break  // Only process first event
            }
        }
        
        await fulfillment(of: [receivedFollowPack, checkedImmediateAvailability, checkedDelayedAvailability], timeout: 60.0)
        
        // Then: This assertion demonstrates the race condition
        // In the current implementation, profiles are NOT available immediately
        // but SHOULD be available after the preloader has time to fetch them
        
        print("📊 FINAL RESULTS:")
        print("   - Profiles available immediately: \(profilesAvailableImmediately.count)/\(allUserKeypairs.count)")
        print("   - Profiles available after delay: \(profilesAvailableAfterDelay.count)/\(allUserKeypairs.count)")
        
        // This is the key assertion that demonstrates the bug:
        // If preloading worked synchronously (or the view waited for preloading),
        // all profiles would be available immediately.
        // But with the current async preloading, they're not.
        XCTAssertLessThan(
            profilesAvailableImmediately.count,
            allUserKeypairs.count,
            "Bug demonstration: Profiles should NOT all be available immediately due to async preloading race condition. " +
            "Got \(profilesAvailableImmediately.count)/\(allUserKeypairs.count) immediately available."
        )
        
        // But they should eventually be available after preloading completes
        XCTAssertEqual(
            profilesAvailableAfterDelay.count,
            allUserKeypairs.count,
            "After preloading delay, all profiles should be available. " +
            "Got \(profilesAvailableAfterDelay.count)/\(allUserKeypairs.count) after delay."
        )
    }
    
    /// Test that measures the actual delay between receiving a follow pack event
    /// and having all profiles available in NDB.
    ///
    /// This helps quantify the user-perceived latency of profile "pop-in".
    func testFollowPackPreloadingDelay() async throws {
        // Given: A relay with a follow pack event containing users and their metadata
        let relay = try await setupRelay(port: 9108)
        let relayUrl = RelayURL(await relay.url().description)!
        
        // Create 3 users with their metadata (smaller set for timing measurement)
        let user1Keypair = generate_new_keypair().to_keypair()
        let user2Keypair = generate_new_keypair().to_keypair()
        let user3Keypair = generate_new_keypair().to_keypair()
        
        let allUserKeypairs = [user1Keypair, user2Keypair, user3Keypair]
        
        let metadataEvents = allUserKeypairs.map { keypair in
            createMetadataEvent(keypair: keypair, displayName: "User \(keypair.pubkey.hex().prefix(8))")!
        }
        
        let packAuthorKeypair = test_keypair
        let followPackEvent = createFollowPackEvent(
            authorKeypair: packAuthorKeypair,
            title: "Timing Test Pack",
            packId: "timing-test-\(UUID().uuidString)",
            userPubkeys: allUserKeypairs.map { $0.pubkey }
        )!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        try await sendEvents([followPackEvent] + metadataEvents, to: relayConnection)
        
        let ndb = await generate_test_damus_state(mock_profile_info: nil).ndb
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        var eventReceivedTime: Date?
        var allProfilesLoadedTime: Date?
        
        let testCompleted = XCTestExpectation(description: "Test completed")
        
        // When: Streaming and measuring time to profile availability
        Task {
            for await _ in networkManager.reader.streamExistingEvents(
                filters: [NostrFilter(kinds: [.follow_list])],
                streamMode: .ndbAndNetworkParallel(networkOptimization: nil),
                preloadStrategy: .preload
            ) {
                eventReceivedTime = Date()
                
                // Poll until all profiles are loaded (max 10 seconds)
                for _ in 0..<100 {
                    try? await Task.sleep(for: .milliseconds(100))
                    
                    var allLoaded = true
                    for keypair in allUserKeypairs {
                        let hasProfile = (try? ndb.lookup_profile(keypair.pubkey, borrow: { pr in pr != nil })) ?? false
                        if !hasProfile {
                            allLoaded = false
                            break
                        }
                    }
                    
                    if allLoaded {
                        allProfilesLoadedTime = Date()
                        break
                    }
                }
                
                testCompleted.fulfill()
                break
            }
        }
        
        await fulfillment(of: [testCompleted], timeout: 30.0)
        
        // Then: Measure and report the delay
        guard let receivedTime = eventReceivedTime else {
            XCTFail("Event was never received")
            return
        }
        
        guard let loadedTime = allProfilesLoadedTime else {
            XCTFail("Profiles were never fully loaded within timeout")
            return
        }
        
        let delay = loadedTime.timeIntervalSince(receivedTime)
        print("⏱️  PRELOAD DELAY MEASUREMENT:")
        print("   - Event received at: \(receivedTime)")
        print("   - All profiles loaded at: \(loadedTime)")
        print("   - Total delay: \(String(format: "%.2f", delay)) seconds")
        
        // But it shouldn't take too long (within reasonable network latency)
        XCTAssertLessThan(
            delay,
            3.0,
            "Preloading should complete within a reasonable time. Actual delay: \(delay)s"
        )
    }
}

// MARK: - Test Doubles

/// Test delegate for NostrNetworkManager that provides minimal configuration for testing
private final class TestNetworkDelegate: NostrNetworkManager.Delegate {
    var ndb: Ndb
    var keypair: Keypair
    var latestRelayListEventIdHex: String?
    var latestContactListEvent: NostrEvent?
    var bootstrapRelays: [RelayURL]
    var developerMode: Bool = false
    var experimentalLocalRelayModelSupport: Bool = false
    var relayModelCache: RelayModelCache
    var relayFilters: RelayFilters
    var nwcWallet: WalletConnectURL?
    
    init(ndb: Ndb, keypair: Keypair, bootstrapRelays: [RelayURL]) {
        self.ndb = ndb
        self.keypair = keypair
        self.bootstrapRelays = bootstrapRelays
        self.relayModelCache = RelayModelCache()
        self.relayFilters = RelayFilters(our_pubkey: keypair.pubkey)
    }
}
