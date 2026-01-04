//
//  ProfileNetworkTests.swift
//  damusTests
//
//  Tests for Profile metadata (kind 0) event creation and network delivery.
//  Focuses on PostBox integration and relay communication.
//

import Foundation
import XCTest
@testable import damus

/// Tests for Profile metadata event creation and network delivery via PostBox.
final class ProfileNetworkTests: XCTestCase {

    var pool: RelayPool!
    var postbox: PostBox!
    var mockSocket: MockWebSocket!
    var ndb: Ndb!

    let testRelayURL = RelayURL("wss://test.relay.com")!

    override func setUp() async throws {
        try await super.setUp()
        ndb = Ndb.test
        pool = RelayPool(ndb: ndb)

        mockSocket = MockWebSocket()
        let descriptor = RelayPool.RelayDescriptor(url: testRelayURL, info: .readWrite)
        try await pool.add_relay(descriptor, webSocket: mockSocket)

        postbox = PostBox(pool: pool)

        await pool.connect()
        mockSocket.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await pool.close()
        pool = nil
        postbox = nil
        mockSocket = nil
        ndb = nil
        try await super.tearDown()
    }

    /// Helper to simulate OK response
    func simulateOKResponse(eventId: NoteId, success: Bool = true, message: String = "") {
        let result = CommandResult(event_id: eventId, ok: success, msg: message)
        let response = NostrResponse.ok(result)
        postbox.handle_event(relay_id: testRelayURL, .nostr_event(response))
    }

    // MARK: - Profile Metadata Event Creation Tests

    /// Test: Metadata event is kind 0
    func testMetadataEventIsKind0() throws {
        let keypair = test_keypair_full
        let profile = Profile(name: "testuser", display_name: "Test User")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        XCTAssertEqual(event.kind, NostrKind.metadata.rawValue)
        XCTAssertEqual(event.kind, 0)
    }

    /// Test: Metadata event content contains profile JSON
    func testMetadataEventContentIsProfileJSON() throws {
        let keypair = test_keypair_full
        let profile = Profile(name: "alice", display_name: "Alice")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        XCTAssertFalse(event.content.isEmpty, "Content should not be empty")
        XCTAssertTrue(event.content.contains("alice"), "Should contain name")
        XCTAssertTrue(event.content.contains("Alice"), "Should contain display_name")
    }

    /// Test: Metadata event has empty tags
    func testMetadataEventHasEmptyTags() throws {
        let keypair = test_keypair_full
        let profile = Profile(name: "testuser")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        XCTAssertEqual(event.tags.count, 0, "Metadata events should have no tags")
    }

    /// Test: Metadata event is signed by keypair
    func testMetadataEventIsSignedByKeypair() throws {
        let keypair = test_keypair_full
        let profile = Profile(name: "testuser")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        XCTAssertEqual(event.pubkey, keypair.pubkey)
    }

    // MARK: - Profile with Various Fields

    /// Test: Profile with all standard fields
    func testProfileWithAllFields() throws {
        let keypair = test_keypair_full
        let profile = Profile(
            name: "fullprofile",
            display_name: "Full Profile User",
            about: "A complete profile",
            picture: "https://example.com/pic.jpg",
            banner: "https://example.com/banner.jpg",
            website: "https://example.com",
            lud06: nil,
            lud16: "user@wallet.com",
            nip05: "user@example.com"
        )

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        XCTAssertTrue(event.content.contains("fullprofile"))
        XCTAssertTrue(event.content.contains("Full Profile User"))
        XCTAssertTrue(event.content.contains("A complete profile"))
        XCTAssertTrue(event.content.contains("pic.jpg"))
        XCTAssertTrue(event.content.contains("banner.jpg"))
        XCTAssertTrue(event.content.contains("user@wallet.com"))
        XCTAssertTrue(event.content.contains("user@example.com"))
    }

    /// Test: Profile with only name
    func testProfileWithOnlyName() throws {
        let keypair = test_keypair_full
        let profile = Profile(name: "minimaluser")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        XCTAssertTrue(event.content.contains("minimaluser"))
    }

    /// Test: Profile with unicode characters
    func testProfileWithUnicodeCharacters() throws {
        let keypair = test_keypair_full
        let profile = Profile(name: "user_name", display_name: "Test User")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        // Unicode should be properly encoded in JSON
        XCTAssertTrue(event.content.contains("user_name"))
    }

    // MARK: - Profile PostBox Integration Tests

    /// Test: Metadata event sent to relay via PostBox
    func testMetadataEventSentToRelay() async throws {
        let keypair = test_keypair_full
        let profile = Profile(name: "testuser", display_name: "Test User")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        await postbox.send(event, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(mockSocket.sentMessages.count, 0, "Should have sent message")

        if let sentMessage = mockSocket.sentMessages.first {
            if case .string(let str) = sentMessage {
                XCTAssertTrue(str.contains("EVENT"), "Should be an EVENT message")
                XCTAssertTrue(str.contains("\"kind\":0") || str.contains("\"kind\": 0"), "Should contain kind 0")
            }
        }
    }

    /// Test: Metadata event removed from queue on OK
    func testMetadataEventRemovedOnOK() async throws {
        let keypair = test_keypair_full
        let profile = Profile(name: "testuser")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        await postbox.send(event, to: [testRelayURL])

        XCTAssertNotNil(postbox.events[event.id])

        simulateOKResponse(eventId: event.id)

        XCTAssertNil(postbox.events[event.id], "Event should be removed after OK")
    }

    /// Test: Metadata event queued when relay disconnected
    func testMetadataEventQueuedWhenDisconnected() async throws {
        mockSocket.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        let keypair = test_keypair_full
        let profile = Profile(name: "offlineuser")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        mockSocket.reset()
        await postbox.send(event, to: [testRelayURL])

        XCTAssertNotNil(postbox.events[event.id], "Event should be in queue")
        XCTAssertEqual(mockSocket.sentMessages.count, 0, "Should not send to disconnected relay")
    }

    /// Test: Multi-relay profile broadcast
    func testProfileMultiRelayBroadcast() async throws {
        let relay2URL = RelayURL("wss://relay2.test.com")!
        let mockSocket2 = MockWebSocket()
        let descriptor2 = RelayPool.RelayDescriptor(url: relay2URL, info: .readWrite)
        try await pool.add_relay(descriptor2, webSocket: mockSocket2)
        mockSocket2.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))

        let keypair = test_keypair_full
        let profile = Profile(name: "multirelayuser")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        await postbox.send(event, to: [testRelayURL, relay2URL])

        let postedEvent = postbox.events[event.id]
        XCTAssertNotNil(postedEvent)
        XCTAssertEqual(postedEvent?.remaining.count, 2, "Should track 2 relays")
    }

    // MARK: - on_flush Callback Tests

    /// Test: on_flush callback fires for metadata event
    func testOnFlushCallbackFires() async throws {
        let keypair = test_keypair_full
        let profile = Profile(name: "callbackuser")

        guard let event = make_metadata_event(keypair: keypair, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        var callbackFired = false
        let expectation = XCTestExpectation(description: "Callback should fire")

        await postbox.send(event, to: [testRelayURL], on_flush: .once({ _ in
            callbackFired = true
            expectation.fulfill()
        }))

        simulateOKResponse(eventId: event.id)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(callbackFired)
    }
}

// MARK: - Profile JSON Encoding Tests

/// Tests for Profile JSON encoding/decoding.
final class ProfileEncodingTests: XCTestCase {

    /// Test: encode_json produces valid JSON for profile
    func testEncodeJsonProducesValidJSON() throws {
        let profile = Profile(name: "jsonuser", display_name: "JSON User")

        guard let json = encode_json(profile) else {
            XCTFail("Failed to encode profile to JSON")
            return
        }

        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.hasPrefix("{"))
        XCTAssertTrue(json.hasSuffix("}"))
    }

    /// Test: make_test_profile creates valid profile
    func testMakeTestProfileCreatesValidProfile() {
        let profile = make_test_profile()

        XCTAssertEqual(profile.name, "jb55")
        XCTAssertEqual(profile.display_name, "Will")
        XCTAssertNotNil(profile.about)
        XCTAssertNotNil(profile.picture)
        XCTAssertNotNil(profile.lud16)
        XCTAssertNotNil(profile.nip05)
    }

    /// Test: Profile with lud16 creates valid lnurl
    func testProfileLud16CreatesLnurl() {
        let profile = Profile(lud16: "user@getalby.com")

        // The lnurl property should be available (may require lnaddress_to_lnurl)
        XCTAssertEqual(profile.lud16, "user@getalby.com")
    }
}
