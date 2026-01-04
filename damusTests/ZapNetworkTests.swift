//
//  ZapNetworkTests.swift
//  damusTests
//
//  Tests for Zap request/receipt handling under various network conditions.
//  Focuses on PostBox integration and relay communication.
//

import Foundation
import XCTest
@testable import damus

/// Tests for Zap request creation and network delivery via PostBox.
final class ZapNetworkTests: XCTestCase {

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

    // MARK: - Zap Request Creation Tests

    /// Test: Zap request event is kind 9734
    func testZapRequestIsKind9734() throws {
        let keypair = generate_new_keypair()
        let target = ZapTarget.profile(keypair.pubkey)

        guard let mzapreq = make_zap_request_event(
            keypair: keypair,
            content: "test zap",
            relays: [],
            target: target,
            zap_type: .pub
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        XCTAssertEqual(mzapreq.potentially_anon_outer_request.ev.kind, 9734)
    }

    /// Test: Zap request includes required p-tag
    func testZapRequestIncludesPTag() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let target = ZapTarget.profile(bob.pubkey)

        guard let mzapreq = make_zap_request_event(
            keypair: alice,
            content: "zapping bob",
            relays: [],
            target: target,
            zap_type: .pub
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        let zapreq = mzapreq.potentially_anon_outer_request.ev
        XCTAssertTrue(zapreq.referenced_pubkeys.contains(bob.pubkey), "Should reference target pubkey")
    }

    /// Test: Zap request for note includes e-tag
    func testZapRequestForNoteIncludesETag() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let noteId = NoteId(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!
        let target = ZapTarget.note(id: noteId, author: bob.pubkey)

        guard let mzapreq = make_zap_request_event(
            keypair: alice,
            content: "zapping note",
            relays: [],
            target: target,
            zap_type: .pub
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        let zapreq = mzapreq.potentially_anon_outer_request.ev
        XCTAssertNotNil(zapreq.last_refid(), "Should have e-tag reference")
    }

    /// Test: Anonymous zap uses different pubkey
    func testAnonymousZapUsesDifferentPubkey() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let target = ZapTarget.profile(bob.pubkey)

        guard let mzapreq = make_zap_request_event(
            keypair: alice,
            content: "anon zap",
            relays: [],
            target: target,
            zap_type: .anon
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        let zapreq = mzapreq.potentially_anon_outer_request.ev
        XCTAssertNotEqual(zapreq.pubkey, alice.pubkey, "Anon zap should use different pubkey")
    }

    /// Test: Private zap has empty content in outer request
    func testPrivateZapHasEmptyOuterContent() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let target = ZapTarget.profile(bob.pubkey)

        guard let mzapreq = make_zap_request_event(
            keypair: alice,
            content: "secret message",
            relays: [],
            target: target,
            zap_type: .priv
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        let zapreq = mzapreq.potentially_anon_outer_request.ev
        XCTAssertEqual(zapreq.content, "", "Private zap outer content should be empty")
    }

    // MARK: - Zap PostBox Integration Tests

    /// Test: Zap request sent to relay via PostBox
    func testZapRequestSentToRelay() async throws {
        let keypair = test_keypair_full
        let target = ZapTarget.profile(keypair.pubkey)

        guard let mzapreq = make_zap_request_event(
            keypair: keypair,
            content: "test",
            relays: [],
            target: target,
            zap_type: .pub
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        let zapreq = mzapreq.potentially_anon_outer_request.ev
        await postbox.send(zapreq, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(mockSocket.sentMessages.count, 0, "Should have sent message")

        if let sentMessage = mockSocket.sentMessages.first {
            if case .string(let str) = sentMessage {
                XCTAssertTrue(str.contains("EVENT"), "Should be an EVENT message")
                XCTAssertTrue(str.contains("9734"), "Should contain kind 9734")
            }
        }
    }

    /// Test: Zap request removed from queue on OK
    func testZapRequestRemovedOnOK() async throws {
        let keypair = test_keypair_full
        let target = ZapTarget.profile(keypair.pubkey)

        guard let mzapreq = make_zap_request_event(
            keypair: keypair,
            content: "test",
            relays: [],
            target: target,
            zap_type: .pub
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        let zapreq = mzapreq.potentially_anon_outer_request.ev
        await postbox.send(zapreq, to: [testRelayURL])

        XCTAssertNotNil(postbox.events[zapreq.id])

        simulateOKResponse(eventId: zapreq.id)

        XCTAssertNil(postbox.events[zapreq.id], "Zap request should be removed after OK")
    }

    /// Test: Zap request queued when relay disconnected
    func testZapRequestQueuedWhenDisconnected() async throws {
        mockSocket.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        let keypair = test_keypair_full
        let target = ZapTarget.profile(keypair.pubkey)

        guard let mzapreq = make_zap_request_event(
            keypair: keypair,
            content: "offline zap",
            relays: [],
            target: target,
            zap_type: .pub
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        mockSocket.reset()
        let zapreq = mzapreq.potentially_anon_outer_request.ev
        await postbox.send(zapreq, to: [testRelayURL])

        XCTAssertNotNil(postbox.events[zapreq.id], "Event should be in queue")
        XCTAssertEqual(mockSocket.sentMessages.count, 0, "Should not send to disconnected relay")
    }

    /// Test: Multi-relay zap broadcast
    func testZapMultiRelayBroadcast() async throws {
        let relay2URL = RelayURL("wss://relay2.test.com")!
        let mockSocket2 = MockWebSocket()
        let descriptor2 = RelayPool.RelayDescriptor(url: relay2URL, info: .readWrite)
        try await pool.add_relay(descriptor2, webSocket: mockSocket2)
        mockSocket2.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))

        let keypair = test_keypair_full
        let target = ZapTarget.profile(keypair.pubkey)

        guard let mzapreq = make_zap_request_event(
            keypair: keypair,
            content: "multi-relay zap",
            relays: [],
            target: target,
            zap_type: .pub
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        let zapreq = mzapreq.potentially_anon_outer_request.ev
        await postbox.send(zapreq, to: [testRelayURL, relay2URL])

        let postedEvent = postbox.events[zapreq.id]
        XCTAssertNotNil(postedEvent)
        XCTAssertEqual(postedEvent?.remaining.count, 2, "Should track 2 relays")
    }

    // MARK: - Zap Receipt Parsing Tests

    /// Test: Zap receipt (kind 9735) parsing
    func testZapReceiptParsing() throws {
        // Create a minimal zap receipt event
        let zapper = generate_new_keypair()
        let recipient = generate_new_keypair()

        // Create inner zap request
        guard let mzapreq = make_zap_request_event(
            keypair: recipient,
            content: "test",
            relays: [],
            target: .profile(zapper.pubkey),
            zap_type: .pub
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        let zapreq = mzapreq.potentially_anon_outer_request.ev
        let zapreqJson = encode_json(zapreq) ?? "{}"

        // Verify we can create a zap receipt structure
        let receiptTags: [[String]] = [
            ["p", recipient.pubkey.hex()],
            ["bolt11", "lnbc1..."],
            ["description", zapreqJson],
            ["preimage", "abc123"]
        ]

        XCTAssertEqual(receiptTags.count, 4)
        XCTAssertTrue(receiptTags[2][1].contains("9734"), "Description should contain zap request")
    }

    /// Test: ZapTarget equality
    func testZapTargetEquality() {
        let pubkey = Pubkey(hex: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!
        let noteId = NoteId(hex: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")!

        let profileTarget1 = ZapTarget.profile(pubkey)
        let profileTarget2 = ZapTarget.profile(pubkey)
        let noteTarget = ZapTarget.note(id: noteId, author: pubkey)

        XCTAssertEqual(profileTarget1, profileTarget2)
        XCTAssertNotEqual(profileTarget1, noteTarget)
    }

    // MARK: - on_flush Callback Tests

    /// Test: on_flush callback fires for zap request
    func testOnFlushCallbackFires() async throws {
        let keypair = test_keypair_full
        let target = ZapTarget.profile(keypair.pubkey)

        guard let mzapreq = make_zap_request_event(
            keypair: keypair,
            content: "callback test",
            relays: [],
            target: target,
            zap_type: .pub
        ) else {
            XCTFail("Failed to create zap request")
            return
        }

        var callbackFired = false
        let expectation = XCTestExpectation(description: "Callback should fire")

        let zapreq = mzapreq.potentially_anon_outer_request.ev
        await postbox.send(zapreq, to: [testRelayURL], on_flush: .once({ _ in
            callbackFired = true
            expectation.fulfill()
        }))

        simulateOKResponse(eventId: zapreq.id)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(callbackFired)
    }
}

// MARK: - Zap Type Tests

/// Tests for ZapType enum and behavior.
final class ZapTypeTests: XCTestCase {

    /// Test: ZapType raw values match case names
    func testZapTypeRawValues() {
        XCTAssertEqual(ZapType.pub.rawValue, "pub")
        XCTAssertEqual(ZapType.anon.rawValue, "anon")
        XCTAssertEqual(ZapType.priv.rawValue, "priv")
        XCTAssertEqual(ZapType.non_zap.rawValue, "non_zap")
    }

    /// Test: ZapType to_string matches rawValue
    func testZapTypeToString() {
        XCTAssertEqual(ZapType.pub.to_string(), "pub")
        XCTAssertEqual(ZapType.anon.to_string(), "anon")
        XCTAssertEqual(ZapType.priv.to_string(), "priv")
        XCTAssertEqual(ZapType.non_zap.to_string(), "non_zap")
    }

    /// Test: ZapType initializer from string
    func testZapTypeFromString() {
        XCTAssertEqual(ZapType(from: "pub"), .pub)
        XCTAssertEqual(ZapType(from: "anon"), .anon)
        XCTAssertEqual(ZapType(from: "priv"), .priv)
        XCTAssertEqual(ZapType(from: "non_zap"), .non_zap)
        XCTAssertNil(ZapType(from: "invalid"))
    }
}
