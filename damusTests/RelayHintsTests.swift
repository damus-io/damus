//
//  RelayHintsTests.swift
//  damus
//
//  Created by Daniel D’Aquino on 2026-02-02.
//

import XCTest
import NostrSDK
@testable import damus

/// Tests for relay hints functionality, ensuring relay hints are correctly extracted and used
/// for ephemeral relay connections per NIP-01 and NIP-10.
///
/// These tests verify that:
/// - Relay hints are correctly extracted from tags
/// - Ephemeral relays can be added and managed by RelayPool
/// - Relay hint lease management prevents premature cleanup
final class RelayHintsTests: XCTestCase {
    
    // MARK: - Helper Functions
    
    /// Creates and runs a local relay on a random available port.
    /// - Returns: The running LocalRelay instance
    private func setupRelay() async throws -> LocalRelay {
        let builder = RelayBuilder()
        let relay = LocalRelay(builder: builder)
        try await relay.run()
        print("Relay url: \(await relay.url())")
        return relay
    }
    
    // MARK: - Test Cases
    
    /// Test that TagSequence correctly extracts relay hints from e-tags per NIP-10.
    /// This verifies the basic relay hint extraction functionality.
    func testTagSequenceExtractsRelayHints() {
        // Given: An e-tag with a relay hint at position 2
        let eventIdHex = "a32d70d331f4bea7a859ac71d85a9b4e0c2d1fa9aaf7237a17f85a6227f52fdb"
        let relayUrl = "wss://relay.example.com"
        
        let tags = [
            ["e", eventIdHex, relayUrl, "reply"]
        ]
        
        let note = NdbNote(content: "test", keypair: test_keypair, kind: 1, tags: tags)!
        
        // When: Accessing the first tag
        let firstTag = note.tags[0]
        
        // Then: Relay hint should be extracted correctly
        XCTAssertEqual(firstTag.relayHint?.absoluteString, relayUrl)
        XCTAssertEqual(firstTag.relayHints.count, 1)
        XCTAssertEqual(firstTag.relayHints.first?.absoluteString, relayUrl)
    }
    
    /// Test that TagSequence handles tags without relay hints gracefully.
    func testTagSequenceHandlesEmptyRelayHint() {
        // Given: An e-tag with an empty relay hint
        let eventIdHex = "a32d70d331f4bea7a859ac71d85a9b4e0c2d1fa9aaf7237a17f85a6227f52fdb"
        
        let tags = [
            ["e", eventIdHex, "", "reply"]
        ]
        
        let note = NdbNote(content: "test", keypair: test_keypair, kind: 1, tags: tags)!
        
        // When: Accessing the first tag
        let firstTag = note.tags[0]
        
        // Then: Relay hint should be nil for empty string
        XCTAssertNil(firstTag.relayHint)
        XCTAssertEqual(firstTag.relayHints.count, 0)
    }
    
    /// Test that TagSequence handles tags with fewer than 3 elements (no relay hint position).
    func testTagSequenceHandlesShortTags() {
        // Given: An e-tag with only 2 elements (no relay hint position)
        let eventIdHex = "a32d70d331f4bea7a859ac71d85a9b4e0c2d1fa9aaf7237a17f85a6227f52fdb"
        
        let tags = [
            ["e", eventIdHex]
        ]
        
        let note = NdbNote(content: "test", keypair: test_keypair, kind: 1, tags: tags)!
        
        // When: Accessing the first tag
        let firstTag = note.tags[0]
        
        // Then: Relay hint should be nil
        XCTAssertNil(firstTag.relayHint)
        XCTAssertEqual(firstTag.relayHints.count, 0)
    }
    
    /// Test that RelayPool can add ephemeral relays.
    /// This verifies the basic ephemeral relay management functionality.
    func testRelayPoolAddsEphemeralRelay() async throws {
        // Given: A relay pool and a relay descriptor marked as ephemeral
        let ndb = await test_damus_state.ndb
        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        
        let testRelay = try await setupRelay()
        let testRelayUrl = RelayURL(await testRelay.url().description)!
        
        let descriptor = RelayPool.RelayDescriptor(url: testRelayUrl, info: .readWrite, variant: .ephemeral)
        
        // When: Adding the ephemeral relay
        try await pool.add_relay(descriptor)
        
        // Then: The relay should be in the pool and marked as ephemeral
        let descriptors = await pool.all_descriptors
        let ephemeralRelays = descriptors.filter { $0.ephemeral }
        
        XCTAssertEqual(ephemeralRelays.count, 1, "Should have exactly one ephemeral relay")
        XCTAssertEqual(ephemeralRelays.first?.url, testRelayUrl)
        XCTAssertTrue(ephemeralRelays.first?.ephemeral ?? false)
        
        // Cleanup
        await pool.close()
    }
    
    /// Test that ephemeral relay lease management works correctly.
    /// This ensures ephemeral relays track leases and can be released.
    func testEphemeralRelayLeaseManagement() async throws {
        // Given: A relay pool with an ephemeral relay
        let ndb = await test_damus_state.ndb
        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        
        let testRelay = try await setupRelay()
        let testRelayUrl = RelayURL(await testRelay.url().description)!
        
        let descriptor = RelayPool.RelayDescriptor(url: testRelayUrl, info: .readWrite, variant: .ephemeral)
        try await pool.add_relay(descriptor)
        
        // When: Acquiring a lease on the ephemeral relay
        await pool.acquireEphemeralRelays([testRelayUrl])
        
        // Then: The relay should still be in the pool
        var descriptors = await pool.all_descriptors
        var ephemeralRelays = descriptors.filter { $0.ephemeral }
        XCTAssertEqual(ephemeralRelays.count, 1, "Should have ephemeral relay after acquiring lease")
        
        // When: Releasing the lease
        await pool.releaseEphemeralRelays([testRelayUrl])
        
        // Give some time for cleanup
        try await Task.sleep(for: .seconds(1))
        
        // Then: The relay should be removed after releasing the lease
        descriptors = await pool.all_descriptors
        ephemeralRelays = descriptors.filter { $0.ephemeral && $0.url == testRelayUrl }
        
        XCTAssertEqual(ephemeralRelays.count, 0, "Ephemeral relay should be removed after releasing lease")
        
        // Cleanup
        await pool.close()
    }
    
    /// Test that multiple leases prevent premature cleanup of ephemeral relays.
    /// This ensures the reference counting mechanism works correctly.
    func testMultipleLeasesPreventsCleanup() async throws {
        // Given: A relay pool with an ephemeral relay
        let ndb = await test_damus_state.ndb
        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        
        let testRelay = try await setupRelay()
        let testRelayUrl = RelayURL(await testRelay.url().description)!
        
        let descriptor = RelayPool.RelayDescriptor(url: testRelayUrl, info: .readWrite, variant: .ephemeral)
        try await pool.add_relay(descriptor)
        
        // When: Acquiring two leases on the same ephemeral relay
        await pool.acquireEphemeralRelays([testRelayUrl])
        await pool.acquireEphemeralRelays([testRelayUrl])
        
        // Then: Releasing one lease should not remove the relay
        await pool.releaseEphemeralRelays([testRelayUrl])
        try await Task.sleep(for: .milliseconds(500))
        
        var descriptors = await pool.all_descriptors
        var ephemeralRelays = descriptors.filter { $0.ephemeral && $0.url == testRelayUrl }
        XCTAssertEqual(ephemeralRelays.count, 1, "Should still have ephemeral relay after releasing one of two leases")
        
        // When: Releasing the second lease
        await pool.releaseEphemeralRelays([testRelayUrl])
        try await Task.sleep(for: .seconds(1))
        
        // Then: The relay should be removed after all leases are released
        descriptors = await pool.all_descriptors
        ephemeralRelays = descriptors.filter { $0.ephemeral && $0.url == testRelayUrl }
        
        XCTAssertEqual(ephemeralRelays.count, 0, "Ephemeral relay should be removed after releasing all leases")
        
        // Cleanup
        await pool.close()
    }
    
    /// Test that ensureConnected adds missing relays as ephemeral.
    /// This verifies the automatic ephemeral relay addition when using relay hints.
    func testEnsureConnectedAddsEphemeralRelays() async throws {
        // Given: A relay pool without any relays
        let ndb = await test_damus_state.ndb
        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        
        let testRelay = try await setupRelay()
        let testRelayUrl = RelayURL(await testRelay.url().description)!
        
        // Initially no relays
        var descriptors = await pool.all_descriptors
        XCTAssertEqual(descriptors.count, 0, "Should have no relays initially")
        
        // When: Ensuring connection to a relay not in the pool
        let connectedRelays = await pool.ensureConnected(to: [testRelayUrl], timeout: .seconds(3))
        
        // Then: The relay should be added as ephemeral
        descriptors = await pool.all_descriptors
        let ephemeralRelays = descriptors.filter { $0.ephemeral }
        
        XCTAssertGreaterThan(descriptors.count, 0, "Should have added the relay")
        XCTAssertEqual(ephemeralRelays.count, 1, "Should have one ephemeral relay")
        XCTAssertEqual(ephemeralRelays.first?.url, testRelayUrl)
        
        print("Connected relays: \(connectedRelays.map { $0.absoluteString })")
        
        // Cleanup
        await pool.close()
    }
    
    /// Test that relay hints enable fetching events from relays not in the user's pool.
    /// This is an end-to-end integration test that verifies:
    /// - A note exists on relayA (with the note)
    /// - User is connected to relayB (empty, no notes)
    /// - Using a relay hint to relayA allows fetching the note successfully
    func testRelayHintFetchesEventFromCorrectRelay() async throws {
        // Given: Two relays - one with a note, one empty
        let relayWithNote = try await setupRelay()
        let emptyRelay = try await setupRelay()
        
        let relayWithNoteUrl = RelayURL(await relayWithNote.url().description)!
        let emptyRelayUrl = RelayURL(await emptyRelay.url().description)!
        
        // Create a test note
        let testNote = NostrEvent(content: "Test note on specific relay", keypair: test_keypair)!
        
        // Send the note to relayWithNote only
        let connectionToRelayWithNote = await connectToRelay(url: relayWithNoteUrl, label: "RelayWithNote")
        sendEvents([testNote], to: connectionToRelayWithNote)
        
        // Wait for the event to be received by the relay
        try await Task.sleep(for: .milliseconds(500))
        
        // When: Network manager is connected ONLY to the empty relay (not relayWithNote)
        let ndb = await test_damus_state.ndb
        let networkManager = try await setupNetworkManager(with: [emptyRelayUrl], ndb: ndb)
        
        // Verify the note is NOT in local NDB yet
        let localNote = try? ndb.lookup_note_and_copy(testNote.id)
        XCTAssertNil(localNote, "Note should not be in local NDB yet")
        
        // Try to fetch WITHOUT relay hint (should fail since note is not on emptyRelay)
        let lenderWithoutHint = try? await networkManager.reader.lookup(noteId: testNote.id, to: nil, timeout: .seconds(2))
        XCTAssertNil(lenderWithoutHint, "Should not find note without relay hint (note is not on emptyRelay)")
        
        // Then: Fetch WITH relay hint to relayWithNote (should succeed)
        let lenderWithHint = try? await networkManager.reader.lookup(noteId: testNote.id, to: [relayWithNoteUrl], timeout: .seconds(5))
        
        XCTAssertNotNil(lenderWithHint, "Should find note using relay hint")
        
        // Verify the found note matches the original
        var foundNote: NostrEvent?
        lenderWithHint?.justUseACopy({ foundNote = $0 })
        
        XCTAssertNotNil(foundNote, "Should be able to extract note from lender")
        XCTAssertEqual(foundNote?.id, testNote.id, "Found note should match original")
        XCTAssertEqual(foundNote?.content, testNote.content, "Note content should match")
        
        // Cleanup
        await networkManager.close()
    }
    
    /// Test that relay hints fall back to broadcasting when hinted relays don't respond.
    /// This verifies the critical fallback mechanism that ensures notes can still be fetched
    /// even when relay hints point to slow or unavailable relays.
    func testRelayHintFallsBackToBroadcastWhenHintsDontRespond() async throws {
        // Given: User has a relay with the note, but relay hint points to a relay WITHOUT the note
        let userRelay = try await setupRelay()
        let slowHintRelay = try await setupRelay()
        
        let userRelayUrl = RelayURL(await userRelay.url().description)!
        let slowHintRelayUrl = RelayURL(await slowHintRelay.url().description)!
        
        // Create a test note
        let testNote = NostrEvent(content: "Note for fallback test", keypair: test_keypair)!
        
        // Send the note ONLY to user's relay (not to the hinted relay)
        let userConnection = await connectToRelay(url: userRelayUrl, label: "UserRelay")
        sendEvents([testNote], to: userConnection)
        
        // Wait for the event to be received by the relay
        try await Task.sleep(for: .milliseconds(500))
        
        // When: Network manager is connected to user's relay
        let ndb = await test_damus_state.ndb
        let networkManager = try await setupNetworkManager(with: [userRelayUrl], ndb: ndb)
        
        // Try to fetch WITH relay hint to slowHintRelay (which doesn't have the note)
        // This should:
        // 1. Try slowHintRelay first (will timeout/fail)
        // 2. Fall back to broadcasting to userRelay
        // 3. Successfully find the note
        let lender = try? await networkManager.reader.lookup(noteId: testNote.id, to: [slowHintRelayUrl], timeout: .seconds(5))
        
        // Then: Note should be found via fallback broadcast to user's relay
        XCTAssertNotNil(lender, "Should find note via fallback broadcast despite bad relay hint")
        
        var foundNote: NostrEvent?
        lender?.justUseACopy({ foundNote = $0 })
        
        XCTAssertNotNil(foundNote, "Should be able to extract note from lender")
        XCTAssertEqual(foundNote?.id, testNote.id, "Found note should match original")
        XCTAssertEqual(foundNote?.content, testNote.content, "Note content should match")
        
        // Cleanup
        await networkManager.close()
    }

    /// Test that toViewOpenAction correctly handles nprofile mentions with relay hints.
    /// This exercises the production code path in LossyLocalNotification.toViewOpenAction.
    func testToViewOpenActionWithNProfileRelayHints() async throws {
        // Given: A relay with a real profile event and an nprofile pointing to that relay
        let authorKeypair = generate_new_keypair().to_keypair()
        let hintedRelay = try await setupRelay()
        let hintedRelayUrl = RelayURL(await hintedRelay.url().description)!
        let profileEvent = NostrEvent(
            content: "{\"name\": \"Hinted User\", \"about\": \"Fetched via nprofile relay hint\"}",
            keypair: authorKeypair,
            kind: 0,
            tags: []
        )!

        let hintedConnection = await connectToRelay(url: hintedRelayUrl, label: "HintedRelay")
        sendEvents([profileEvent], to: hintedConnection)
        try await Task.sleep(for: .milliseconds(500))

        let nprofile = NProfile(author: authorKeypair.pubkey, relays: [hintedRelayUrl])
        let mentionRef = MentionRef(nip19: .nprofile(nprofile))
        let notification = LossyLocalNotification(type: .profile_zap, mention: mentionRef)
        let damus_state = await test_damus_state

        // When: Converting the notification to a view open action
        let openAction = notification.toViewOpenAction(damus_state: damus_state)

        // Then: The route is correct
        guard case .route(let route) = openAction else {
            XCTFail("Expected route action, got \(openAction)")
            return
        }
        guard case .ProfileByKey(let pubkey) = route else {
            XCTFail("Expected ProfileByKey route, got \(route)")
            return
        }
        XCTAssertEqual(pubkey, authorKeypair.pubkey, "Route should contain the correct pubkey from nprofile")

        // And: The side effect happened (relay hints were consumed to prefetch profile data)
        let fetchedProfile = await waitForProfile(id: authorKeypair.pubkey, in: damus_state.profiles, timeoutSeconds: 5.0)
        XCTAssertNotNil(fetchedProfile, "Expected profile prefetch using nprofile relay hints")
        XCTAssertEqual(fetchedProfile?.name, "Hinted User", "Fetched profile should match relay-hosted profile data")
    }

    /// Test that toViewOpenAction handles nprofile without relay hints (empty relays).
    func testToViewOpenActionWithNProfileNoRelayHints() async throws {
        // Given: A notification with an nprofile mention without relay hints and a pubkey
        // that does not already exist in shared test profile storage
        let damus_state = await test_damus_state
        let authorPubkey = makeUnusedPubkey(in: damus_state.profiles)
        XCTAssertNil(try? damus_state.profiles.lookup(id: authorPubkey), "Test precondition failed: pubkey must be absent before opening action")

        let nprofile = NProfile(author: authorPubkey, relays: [])
        let mentionRef = MentionRef(nip19: .nprofile(nprofile))
        let notification = LossyLocalNotification(type: .profile_zap, mention: mentionRef)

        // When: Converting the notification to a view open action
        let openAction = notification.toViewOpenAction(damus_state: damus_state)

        // Then: The action is still the expected profile route
        guard case .route(let route) = openAction else {
            XCTFail("Expected route action, got \(openAction)")
            return
        }
        guard case .ProfileByKey(let pubkey) = route else {
            XCTFail("Expected ProfileByKey route, got \(route)")
            return
        }
        XCTAssertEqual(pubkey, authorPubkey, "Route should contain the correct pubkey from nprofile")

        // And: No relay-hint prefetch side effect is triggered for empty relay hints
        try await Task.sleep(for: .milliseconds(250))
        let profile = try? damus_state.profiles.lookup(id: authorPubkey)
        XCTAssertNil(profile, "No profile prefetch should occur when nprofile relay hints are empty")
    }

    /// Test that relay hints from NIP-19 nevent entities are correctly used for lookups.
    /// This verifies that nevent-style relay hints (common in nostr: URLs) work correctly.
    func testRelayHintsFromNEventEntity() async throws {
        // Given: A relay with a note, and nevent with relay hints
        let hintedRelay = try await setupRelay()
        let emptyRelay = try await setupRelay()
        
        let hintedRelayUrl = RelayURL(await hintedRelay.url().description)!
        let emptyRelayUrl = RelayURL(await emptyRelay.url().description)!
        
        // Create a test note and send it to the hinted relay
        let testNote = NostrEvent(content: "Note for nevent test", keypair: test_keypair)!
        
        let hintedConnection = await connectToRelay(url: hintedRelayUrl, label: "HintedRelay")
        sendEvents([testNote], to: hintedConnection)
        
        try await Task.sleep(for: .milliseconds(500))
        
        // When: Network manager is connected ONLY to empty relay
        let ndb = await test_damus_state.ndb
        let networkManager = try await setupNetworkManager(with: [emptyRelayUrl], ndb: ndb)
        
        // Create an NEvent with relay hints (simulating NIP-19 parsing)
        let nevent = NEvent(noteid: testNote.id, relays: [hintedRelayUrl])
        
        // Verify nevent has relay hints
        XCTAssertEqual(nevent.relays.count, 1, "NEvent should have one relay hint")
        XCTAssertEqual(nevent.relays.first, hintedRelayUrl, "NEvent relay hint should match")
        
        // Then: Use findEvent with nevent's relay hints (as it would be used in real code)
        let targetRelays = nevent.relays.isEmpty ? nil : nevent.relays
        let result = await networkManager.reader.findEvent(query: .event(evid: nevent.noteid, find_from: targetRelays))
        
        // Verify we got the event back with network source attribution
        guard case .event(let foundNote, let source) = result else {
            XCTFail("Should find note using nevent relay hints via findEvent")
            return
        }

        XCTAssertEqual(foundNote.id, testNote.id, "Found note should match nevent note ID")
        XCTAssertEqual(foundNote.content, testNote.content, "Found note content should match")
        guard case .network = source else {
            XCTFail("Event from relay should have .network source, got \(source)")
            return
        }
        
        // Cleanup
        await networkManager.close()
    }

    /// Test that findEvent rejects metadata events whose pubkey does not match the requested profile.
    /// A non-compliant relay could return kind-0 metadata for a different pubkey than requested.
    /// The pubkey guard in findEvent must prevent this from being accepted.
    func testFindEventRejectsMismatchedProfilePubkey() async throws {
        // Given: A relay that has metadata for keypair B, but we query for keypair A
        let relay = try await setupRelay()
        let relayUrl = RelayURL(await relay.url().description)!

        let keypairA = generate_new_keypair().to_keypair()
        let keypairB = generate_new_keypair().to_keypair()

        // Publish keypair B's metadata to the relay
        let metadataB = NostrEvent(content: "{\"name\":\"attacker\"}", keypair: keypairB, kind: NostrKind.metadata.rawValue)!
        let connection = await connectToRelay(url: relayUrl, label: "MismatchRelay")
        sendEvents([metadataB], to: connection)

        try await Task.sleep(for: .milliseconds(500))

        // When: Network manager queries for keypair A's profile using the relay hint
        let ndb = await test_damus_state.ndb
        let networkManager = try await setupNetworkManager(with: [], ndb: ndb)

        let result = await networkManager.reader.findEvent(query: .profile(pubkey: keypairA.pubkey, find_from: [relayUrl]))

        // Then: findEvent must NOT return keypair B's metadata as keypair A's profile
        XCTAssertNil(result, "findEvent must reject metadata whose pubkey does not match the requested profile")

        // Cleanup
        await networkManager.close()
    }

    /// Test that relay hints work correctly when some events are cached in NDB.
    /// This verifies that cached events are returned from NDB and relay hints are only
    /// used for non-cached events, avoiding unnecessary network calls.
    func testRelayHintsWithNDBCachedEvents() async throws {
        // Given: Some notes cached in NDB, one note on a relay
        let relay = try await setupRelay()
        let relayUrl = RelayURL(await relay.url().description)!
        
        // Create three notes
        let cachedNoteA = NostrEvent(content: "Cached note A", keypair: test_keypair)!
        let cachedNoteB = NostrEvent(content: "Cached note B", keypair: test_keypair)!
        let uncachedNoteC = NostrEvent(content: "Uncached note C", keypair: test_keypair)!
        
        // Store A and B in NDB (cached)
        let ndb = await test_damus_state.ndb
        storeEventsInNdb([cachedNoteA, cachedNoteB], ndb: ndb)
        
        // Send only C to the relay
        let connection = await connectToRelay(url: relayUrl, label: "Relay")
        sendEvents([uncachedNoteC], to: connection)
        
        try await Task.sleep(for: .milliseconds(500))
        
        // When: Network manager is set up
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        // Then: Fetch all three notes with relay hints
        
        // Fetch cached note A (should come from NDB, not network)
        let lenderA = try? await networkManager.reader.lookup(noteId: cachedNoteA.id, to: [relayUrl], timeout: .seconds(3))
        XCTAssertNotNil(lenderA, "Should find cached note A")
        
        var foundA: NostrEvent?
        lenderA?.justUseACopy({ foundA = $0 })
        XCTAssertEqual(foundA?.id, cachedNoteA.id, "Cached note A should match")
        XCTAssertEqual(foundA?.content, "Cached note A", "Cached note A content should match")
        
        // Fetch cached note B (should come from NDB, not network)
        let lenderB = try? await networkManager.reader.lookup(noteId: cachedNoteB.id, to: [relayUrl], timeout: .seconds(3))
        XCTAssertNotNil(lenderB, "Should find cached note B")
        
        var foundB: NostrEvent?
        lenderB?.justUseACopy({ foundB = $0 })
        XCTAssertEqual(foundB?.id, cachedNoteB.id, "Cached note B should match")
        XCTAssertEqual(foundB?.content, "Cached note B", "Cached note B content should match")
        
        // Fetch uncached note C (should use relay hints to fetch from network)
        let lenderC = try? await networkManager.reader.lookup(noteId: uncachedNoteC.id, to: [relayUrl], timeout: .seconds(3))
        XCTAssertNotNil(lenderC, "Should find uncached note C via relay hints")
        
        var foundC: NostrEvent?
        lenderC?.justUseACopy({ foundC = $0 })
        XCTAssertEqual(foundC?.id, uncachedNoteC.id, "Uncached note C should match")
        XCTAssertEqual(foundC?.content, "Uncached note C", "Uncached note C content should match")
        
        // Verify all notes were found correctly
        XCTAssertNotNil(foundA, "Note A should be found from cache")
        XCTAssertNotNil(foundB, "Note B should be found from cache")
        XCTAssertNotNil(foundC, "Note C should be found from network")
        
        // Cleanup
        await networkManager.close()
    }
    
    // MARK: - Helper Functions for Integration Test
    
    /// Connects to a relay and waits for the connection to be established.
    /// - Parameters:
    ///   - url: The relay URL to connect to
    ///   - label: Optional label for logging
    /// - Returns: The connected RelayConnection instance
    private func connectToRelay(url: RelayURL, label: String = "") async -> RelayConnection {
        var connectionContinuation: CheckedContinuation<Void, Never>?
        
        let relayConnection = RelayConnection(url: url, handleEvent: { _ in }, processUnverifiedWSEvent: { wsEvent in
            let prefix = label.isEmpty ? "" : "(\(label)) "
            switch wsEvent {
            case .connected:
                connectionContinuation?.resume()
            case .message(let message):
                print("RELAY_HINTS_TEST \(prefix): Received: \(message)")
            case .disconnected(let closeCode, let string):
                print("RELAY_HINTS_TEST \(prefix): Disconnected: \(closeCode); \(String(describing: string))")
            case .error(let error):
                print("RELAY_HINTS_TEST \(prefix): Received error: \(error)")
            }
        })
        // Wait for connection to be established
        await withCheckedContinuation { continuation in
            connectionContinuation = continuation
            relayConnection.connect()
        }
        
        return relayConnection
    }
    
    /// Sends events to a relay connection.
    /// - Parameters:
    ///   - events: Array of NostrEvent to send
    ///   - connection: The RelayConnection to send events through
    private func sendEvents(_ events: [NostrEvent], to connection: RelayConnection) {
        for event in events {
            connection.send(.typical(.event(event)))
        }
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
    
    /// Sets up a NostrNetworkManager with the specified relay URLs.
    /// - Parameters:
    ///   - urls: Array of RelayURL to add to the manager
    ///   - ndb: The Ndb instance to use
    /// - Returns: Configured and connected NostrNetworkManager
    private func setupNetworkManager(with urls: [RelayURL], ndb: Ndb) async throws -> NostrNetworkManager {
        let delegate = TestNetworkDelegate(ndb: ndb, keypair: test_keypair, bootstrapRelays: urls)
        let networkManager = NostrNetworkManager(delegate: delegate, addNdbToRelayPool: true)
        
        // Manually add relays to the pool
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
        
        // Only connect and wait if we have relays to connect to
        if !urls.isEmpty {
            await networkManager.userRelayList.connect()
            // Wait for relay pool to be ready
            try await Task.sleep(for: .seconds(2))
        }
        
        return networkManager
    }

    /// Polls for a profile to appear in storage within a timeout window.
    /// - Parameters:
    ///   - id: The pubkey to lookup.
    ///   - profiles: The Profiles storage object.
    ///   - timeoutSeconds: Maximum time to wait.
    /// - Returns: The fetched profile if available before timeout; otherwise nil.
    private func waitForProfile(id: Pubkey, in profiles: Profiles, timeoutSeconds: TimeInterval) async -> Profile? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let profile = try? profiles.lookup(id: id) {
                return profile
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Generates a pubkey that is currently absent from the provided profile store.
    /// This avoids false failures caused by shared global test state.
    /// - Parameter profiles: The profile storage to check for preexisting records.
    /// - Returns: A pubkey that is not currently present in storage.
    private func makeUnusedPubkey(in profiles: Profiles) -> Pubkey {
        for _ in 0..<64 {
            let candidate = generate_new_keypair().to_keypair().pubkey
            if (try? profiles.lookup(id: candidate)) == nil {
                return candidate
            }
        }
        // Fallback is practically unreachable; retained to keep control flow explicit.
        return generate_new_keypair().to_keypair().pubkey
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
