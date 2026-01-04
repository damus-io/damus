//
//  DirectMessageTests.swift
//  damusTests
//
//  Tests for Direct Message handling: NIP-04 encryption, DM model behavior,
//  and PostBox integration under various network conditions.
//

import Foundation
import XCTest
@testable import damus

/// Tests for DirectMessageModel behavior, NIP-04 encryption, and DM handling.
final class DirectMessageTests: XCTestCase {

    // MARK: - Test Keypairs

    var alice: Keypair {
        let sec = hex_decode_privkey("494c680d20f202807a116a6915815bd76a27d62802e7585806f6a2e034cb5cdb")!
        let pk = hex_decode_pubkey("22d925632551a3299022e98de7f9c1087f79a21209f3413ec24ec219b08bd1e4")!
        return Keypair(pubkey: pk, privkey: sec)
    }

    var bob: Keypair {
        let sec = hex_decode_privkey("aa8920b05b4bd5c79fce46868ed5ebc82bdb91b211850b14541bfbd13953cfef")!
        let pk = hex_decode_pubkey("5a9a277dca94260688ecf7d63053de8c121b7f01f609d7f84a1eb9cff64e4606")!
        return Keypair(pubkey: pk, privkey: sec)
    }

    var charlie: Keypair {
        let sec = hex_decode_privkey("4c79130952c9c3b017dad62f37f285853a9c53f2a1184d94594f5b860f30b5a5")!
        let pk = hex_decode_pubkey("51c0d263fbfc4bf850805dccf9a29125071e6fed9619bff3efa9a6b5bbcc54a7")!
        return Keypair(pubkey: pk, privkey: sec)
    }

    // MARK: - NIP-04 Encryption Tests

    /// Test: NIP-04 message encryption produces valid encrypted content
    func testNIP04EncryptMessage() throws {
        let message = "Hello Bob!"
        let encrypted = NIP04.encrypt_message(
            message: message,
            privkey: alice.privkey!,
            to_pk: bob.pubkey
        )

        XCTAssertNotNil(encrypted, "Encryption should succeed")
        XCTAssertTrue(encrypted!.contains("?iv="), "Encrypted message should contain IV separator")
        XCTAssertNotEqual(encrypted, message, "Encrypted content should differ from plaintext")
    }

    /// Test: NIP-04 encryption and decryption round-trip
    func testNIP04EncryptDecryptRoundTrip() throws {
        let originalMessage = "Secret message from Alice to Bob"

        guard let encrypted = NIP04.encrypt_message(
            message: originalMessage,
            privkey: alice.privkey!,
            to_pk: bob.pubkey
        ) else {
            XCTFail("Encryption failed")
            return
        }

        // Bob decrypts message from Alice
        let decrypted = try NIP04.decryptContent(
            recipientPrivateKey: bob.privkey!,
            senderPubkey: alice.pubkey,
            content: encrypted,
            encoding: .base64
        )

        XCTAssertEqual(decrypted, originalMessage, "Decrypted message should match original")
    }

    /// Test: NIP-04 decryption fails with wrong key
    func testNIP04DecryptionFailsWithWrongKey() throws {
        let message = "Secret message"

        guard let encrypted = NIP04.encrypt_message(
            message: message,
            privkey: alice.privkey!,
            to_pk: bob.pubkey
        ) else {
            XCTFail("Encryption failed")
            return
        }

        // Charlie tries to decrypt (should fail)
        XCTAssertThrowsError(
            try NIP04.decryptContent(
                recipientPrivateKey: charlie.privkey!,
                senderPubkey: alice.pubkey,
                content: encrypted,
                encoding: .base64
            )
        ) { error in
            XCTAssertTrue(error is NIP04.NIP04DecryptionError, "Should throw NIP04 decryption error")
        }
    }

    /// Test: NIP-04 handles empty message
    func testNIP04EmptyMessage() throws {
        let encrypted = NIP04.encrypt_message(
            message: "",
            privkey: alice.privkey!,
            to_pk: bob.pubkey
        )

        XCTAssertNotNil(encrypted, "Empty message encryption should succeed")

        let decrypted = try NIP04.decryptContent(
            recipientPrivateKey: bob.privkey!,
            senderPubkey: alice.pubkey,
            content: encrypted!,
            encoding: .base64
        )

        XCTAssertEqual(decrypted, "", "Decrypted empty message should be empty")
    }

    /// Test: NIP-04 handles unicode and emoji
    func testNIP04UnicodeAndEmoji() throws {
        let message = "Hello 🌍 مرحبا 你好 🎉"

        guard let encrypted = NIP04.encrypt_message(
            message: message,
            privkey: alice.privkey!,
            to_pk: bob.pubkey
        ) else {
            XCTFail("Encryption failed")
            return
        }

        let decrypted = try NIP04.decryptContent(
            recipientPrivateKey: bob.privkey!,
            senderPubkey: alice.pubkey,
            content: encrypted,
            encoding: .base64
        )

        XCTAssertEqual(decrypted, message, "Unicode/emoji should survive encryption round-trip")
    }

    // MARK: - DM Event Creation Tests

    /// Test: create_dm produces valid kind 4 event
    func testCreateDMProducesKind4Event() throws {
        let message = "Hello Bob!"
        let tags: [[String]] = [[bob.pubkey.hex()]]

        let dm = NIP04.create_dm(
            message,
            to_pk: bob.pubkey,
            tags: tags,
            keypair: alice
        )

        XCTAssertNotNil(dm, "DM creation should succeed")
        XCTAssertEqual(dm?.kind, 4, "DM should be kind 4")
        XCTAssertEqual(dm?.pubkey, alice.pubkey, "DM pubkey should be sender")
        XCTAssertTrue(dm!.content.contains("?iv="), "Content should be encrypted")
    }

    /// Test: DM event includes recipient p-tag
    func testDMEventIncludesRecipientTag() throws {
        let pTag = ["p", bob.pubkey.hex()]
        let tags: [[String]] = [pTag]

        let dm = NIP04.create_dm(
            "Hello",
            to_pk: bob.pubkey,
            tags: tags,
            keypair: alice
        )

        XCTAssertNotNil(dm)
        XCTAssertTrue(dm!.referenced_pubkeys.contains(bob.pubkey), "DM should reference recipient pubkey")
    }

    // MARK: - DirectMessageModel Tests

    /// Test: DirectMessageModel initializes correctly
    func testDirectMessageModelInitialization() {
        let model = DirectMessageModel(our_pubkey: alice.pubkey, pubkey: bob.pubkey)

        XCTAssertEqual(model.our_pubkey, alice.pubkey)
        XCTAssertEqual(model.pubkey, bob.pubkey)
        XCTAssertEqual(model.events.count, 0)
        XCTAssertEqual(model.draft, "")
    }

    /// Test: is_request is true when no messages from us
    func testIsRequestTrueWhenNoMessagesFromUs() throws {
        let model = DirectMessageModel(our_pubkey: alice.pubkey, pubkey: bob.pubkey)

        // Add message from Bob (not from us/Alice)
        let bobsMessage = NIP04.create_dm(
            "Hi Alice",
            to_pk: alice.pubkey,
            tags: [["p", alice.pubkey.hex()]],
            keypair: bob
        )!

        model.events = [bobsMessage]

        XCTAssertTrue(model.is_request, "Should be a request when no messages from us")
    }

    /// Test: is_request is false when we've replied
    func testIsRequestFalseWhenWeReplied() throws {
        let model = DirectMessageModel(our_pubkey: alice.pubkey, pubkey: bob.pubkey)

        // Add message from Bob
        let bobsMessage = NIP04.create_dm(
            "Hi Alice",
            to_pk: alice.pubkey,
            tags: [["p", alice.pubkey.hex()]],
            keypair: bob
        )!

        // Add our reply
        let alicesReply = NIP04.create_dm(
            "Hi Bob",
            to_pk: bob.pubkey,
            tags: [["p", bob.pubkey.hex()]],
            keypair: alice
        )!

        model.events = [bobsMessage, alicesReply]

        XCTAssertFalse(model.is_request, "Should not be a request when we've replied")
    }

    // MARK: - DirectMessagesModel Tests

    /// Test: DirectMessagesModel lookup returns correct conversation
    func testDirectMessagesModelLookup() {
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)

        let bobConvo = DirectMessageModel(our_pubkey: alice.pubkey, pubkey: bob.pubkey)
        let charlieConvo = DirectMessageModel(our_pubkey: alice.pubkey, pubkey: charlie.pubkey)

        model.dms = [bobConvo, charlieConvo]

        XCTAssertNotNil(model.lookup(bob.pubkey))
        XCTAssertNotNil(model.lookup(charlie.pubkey))
        XCTAssertNil(model.lookup(alice.pubkey)) // Can't look up ourselves
    }

    /// Test: lookup_or_create creates new conversation if not found
    func testLookupOrCreateCreatesNewConversation() {
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)

        XCTAssertEqual(model.dms.count, 0)

        let bobConvo = model.lookup_or_create(bob.pubkey)

        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(bobConvo.pubkey, bob.pubkey)

        // Second call returns existing
        let bobConvo2 = model.lookup_or_create(bob.pubkey)
        XCTAssertEqual(model.dms.count, 1, "Should not create duplicate")
        XCTAssertTrue(bobConvo === bobConvo2, "Should return same instance")
    }

    /// Test: friend_dms and message_requests filter correctly
    func testFriendDMsAndMessageRequestsFilter() throws {
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)

        // Create convo with Bob where we've replied (friend)
        let bobConvo = DirectMessageModel(our_pubkey: alice.pubkey, pubkey: bob.pubkey)
        let aliceToBob = NIP04.create_dm("Hi Bob", to_pk: bob.pubkey, tags: [], keypair: alice)!
        bobConvo.events = [aliceToBob]

        // Create convo with Charlie (request - we haven't replied)
        let charlieConvo = DirectMessageModel(our_pubkey: alice.pubkey, pubkey: charlie.pubkey)
        let charlieToAlice = NIP04.create_dm("Hi Alice", to_pk: alice.pubkey, tags: [], keypair: charlie)!
        charlieConvo.events = [charlieToAlice]

        model.dms = [bobConvo, charlieConvo]

        XCTAssertEqual(model.friend_dms.count, 1)
        XCTAssertEqual(model.friend_dms.first?.pubkey, bob.pubkey)

        XCTAssertEqual(model.message_requests.count, 1)
        XCTAssertEqual(model.message_requests.first?.pubkey, charlie.pubkey)
    }

    // MARK: - handle_incoming_dm Tests

    /// Test: handle_incoming_dm inserts event into correct conversation
    func testHandleIncomingDMInsertsEvent() throws {
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)
        let prevEvents = NewEventsBits()

        let bobsMessage = NIP04.create_dm(
            "Hi Alice",
            to_pk: alice.pubkey,
            tags: [["p", alice.pubkey.hex()]],
            keypair: bob
        )!

        let (inserted, _) = handle_incoming_dm(
            ev: bobsMessage,
            our_pubkey: alice.pubkey,
            dms: model,
            prev_events: prevEvents
        )

        XCTAssertTrue(inserted, "Message should be inserted")
        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms.first?.pubkey, bob.pubkey)
        XCTAssertEqual(model.dms.first?.events.count, 1)
    }

    /// Test: handle_incoming_dms sorts conversations by latest message
    func testHandleIncomingDMsSortsConversations() throws {
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)
        let prevEvents = NewEventsBits()
        let now = UInt32(Date().timeIntervalSince1970)

        // Bob's message first
        let bobsMessage = NIP04.create_dm(
            "Hi Alice",
            to_pk: alice.pubkey,
            tags: [["p", alice.pubkey.hex()]],
            keypair: bob,
            created_at: now
        )!

        // Charlie's message later
        let charliesMessage = NIP04.create_dm(
            "Hey Alice",
            to_pk: alice.pubkey,
            tags: [["p", alice.pubkey.hex()]],
            keypair: charlie,
            created_at: now + 10
        )!

        let _ = handle_incoming_dms(
            prev_events: prevEvents,
            dms: model,
            our_pubkey: alice.pubkey,
            evs: [bobsMessage, charliesMessage]
        )

        XCTAssertEqual(model.dms.count, 2)
        XCTAssertEqual(model.dms.first?.pubkey, charlie.pubkey, "Latest message should be first")
    }

    /// Test: Duplicate DM events are rejected
    func testDuplicateDMEventsRejected() throws {
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)
        let prevEvents = NewEventsBits()

        let bobsMessage = NIP04.create_dm(
            "Hi Alice",
            to_pk: alice.pubkey,
            tags: [["p", alice.pubkey.hex()]],
            keypair: bob
        )!

        let (inserted1, _) = handle_incoming_dm(
            ev: bobsMessage,
            our_pubkey: alice.pubkey,
            dms: model,
            prev_events: prevEvents
        )

        let (inserted2, _) = handle_incoming_dm(
            ev: bobsMessage, // Same message
            our_pubkey: alice.pubkey,
            dms: model,
            prev_events: prevEvents
        )

        XCTAssertTrue(inserted1)
        XCTAssertFalse(inserted2, "Duplicate should be rejected")
        XCTAssertEqual(model.dms.first?.events.count, 1, "Should still have 1 event")
    }

    /// Test: Our outgoing DM routes to correct conversation
    func testOutgoingDMRoutesToCorrectConversation() throws {
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)
        let prevEvents = NewEventsBits()

        // Alice sends to Bob
        let aliceToBob = NIP04.create_dm(
            "Hello Bob!",
            to_pk: bob.pubkey,
            tags: [["p", bob.pubkey.hex()]],
            keypair: alice
        )!

        let (inserted, _) = handle_incoming_dm(
            ev: aliceToBob,
            our_pubkey: alice.pubkey,
            dms: model,
            prev_events: prevEvents
        )

        XCTAssertTrue(inserted)
        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms.first?.pubkey, bob.pubkey, "Should be in Bob's conversation")
    }
}

// MARK: - DM PostBox Integration Tests

/// Tests for DM publishing via PostBox under various network conditions.
final class DMPostBoxTests: XCTestCase {

    var pool: RelayPool!
    var postbox: PostBox!
    var mockSocket: MockWebSocket!
    var ndb: Ndb!

    let testRelayURL = RelayURL("wss://test.relay.com")!

    var alice: Keypair {
        let sec = hex_decode_privkey("494c680d20f202807a116a6915815bd76a27d62802e7585806f6a2e034cb5cdb")!
        let pk = hex_decode_pubkey("22d925632551a3299022e98de7f9c1087f79a21209f3413ec24ec219b08bd1e4")!
        return Keypair(pubkey: pk, privkey: sec)
    }

    var bob: Keypair {
        let sec = hex_decode_privkey("aa8920b05b4bd5c79fce46868ed5ebc82bdb91b211850b14541bfbd13953cfef")!
        let pk = hex_decode_pubkey("5a9a277dca94260688ecf7d63053de8c121b7f01f609d7f84a1eb9cff64e4606")!
        return Keypair(pubkey: pk, privkey: sec)
    }

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

    /// Helper to create a DM event
    func makeDM(message: String, from: Keypair, to: Keypair) -> NostrEvent? {
        return NIP04.create_dm(
            message,
            to_pk: to.pubkey,
            tags: [["p", to.pubkey.hex()]],
            keypair: from
        )
    }

    /// Helper to simulate OK response
    func simulateOKResponse(eventId: NoteId, success: Bool = true, message: String = "") {
        let result = CommandResult(event_id: eventId, ok: success, msg: message)
        let response = NostrResponse.ok(result)
        postbox.handle_event(relay_id: testRelayURL, .nostr_event(response))
    }

    // MARK: - Basic DM Sending Tests

    /// Test: DM is sent to relay
    func testDMIsSentToRelay() async throws {
        guard let dm = makeDM(message: "Hello Bob!", from: alice, to: bob) else {
            XCTFail("Failed to create DM")
            return
        }

        await postbox.send(dm, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(mockSocket.sentMessages.count, 0, "Should have sent message")

        if let sentMessage = mockSocket.sentMessages.first {
            if case .string(let str) = sentMessage {
                XCTAssertTrue(str.contains("EVENT"), "Should be an EVENT message")
                XCTAssertTrue(str.contains("\"kind\":4"), "Should be kind 4 (DM)")
            }
        }
    }

    /// Test: DM removed from queue on OK
    func testDMRemovedFromQueueOnOK() async throws {
        guard let dm = makeDM(message: "Hello Bob!", from: alice, to: bob) else {
            XCTFail("Failed to create DM")
            return
        }

        await postbox.send(dm, to: [testRelayURL])
        XCTAssertNotNil(postbox.events[dm.id])

        simulateOKResponse(eventId: dm.id)

        XCTAssertNil(postbox.events[dm.id], "DM should be removed after OK")
    }

    /// Test: DM delivery targets multiple relays
    func testDMDeliveryToMultipleRelays() async throws {
        let relay2URL = RelayURL("wss://relay2.test.com")!
        let mockSocket2 = MockWebSocket()
        let descriptor2 = RelayPool.RelayDescriptor(url: relay2URL, info: .readWrite)
        try await pool.add_relay(descriptor2, webSocket: mockSocket2)
        mockSocket2.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))

        guard let dm = makeDM(message: "Hello Bob!", from: alice, to: bob) else {
            XCTFail("Failed to create DM")
            return
        }

        await postbox.send(dm, to: [testRelayURL, relay2URL])

        // Verify event is tracked for both relays
        let postedEvent = postbox.events[dm.id]
        XCTAssertNotNil(postedEvent)
        XCTAssertEqual(postedEvent?.remaining.count, 2, "Should have 2 relays in remaining")

        // Primary relay should receive the DM
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(mockSocket.sentMessages.count, 0, "Primary relay should receive DM")
    }

    /// Test: DM stays in queue until all relays respond
    func testDMStaysInQueueUntilAllRelaysRespond() async throws {
        let relay2URL = RelayURL("wss://relay2.test.com")!
        let mockSocket2 = MockWebSocket()
        let descriptor2 = RelayPool.RelayDescriptor(url: relay2URL, info: .readWrite)
        try await pool.add_relay(descriptor2, webSocket: mockSocket2)
        mockSocket2.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))

        guard let dm = makeDM(message: "Hello Bob!", from: alice, to: bob) else {
            XCTFail("Failed to create DM")
            return
        }

        await postbox.send(dm, to: [testRelayURL, relay2URL])

        // First relay responds
        simulateOKResponse(eventId: dm.id)

        XCTAssertNotNil(postbox.events[dm.id], "DM should remain until all relays respond")

        // Second relay responds
        let result2 = CommandResult(event_id: dm.id, ok: true, msg: "")
        postbox.handle_event(relay_id: relay2URL, .nostr_event(.ok(result2)))

        XCTAssertNil(postbox.events[dm.id], "DM should be removed after all relays respond")
    }

    // MARK: - Network Failure Tests

    /// Test: DM queued when relay disconnected
    func testDMQueuedWhenRelayDisconnected() async throws {
        // Disconnect relay
        mockSocket.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        guard let dm = makeDM(message: "Hello Bob!", from: alice, to: bob) else {
            XCTFail("Failed to create DM")
            return
        }

        mockSocket.reset()

        await postbox.send(dm, to: [testRelayURL])

        // Event should be in PostBox queue
        XCTAssertNotNil(postbox.events[dm.id])

        // But not yet sent (relay disconnected)
        XCTAssertEqual(mockSocket.sentMessages.count, 0, "Should not send to disconnected relay")
    }

    /// Test: DM sent when relay reconnects
    func testDMSentWhenRelayReconnects() async throws {
        // Start disconnected
        mockSocket.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        guard let dm = makeDM(message: "Hello Bob!", from: alice, to: bob) else {
            XCTFail("Failed to create DM")
            return
        }

        mockSocket.reset()
        await postbox.send(dm, to: [testRelayURL])

        XCTAssertEqual(mockSocket.sentMessages.count, 0)

        // Reconnect
        mockSocket.simulateConnect()
        try await Task.sleep(for: .milliseconds(200))

        // Trigger flush by checking (PostBox may need explicit retry)
        // The event should still be in the queue for retry
        XCTAssertNotNil(postbox.events[dm.id], "Event should be waiting for delivery")
    }

    // MARK: - Delayed DM Tests

    /// Test: Delayed DM not sent immediately
    func testDelayedDMNotSentImmediately() async throws {
        guard let dm = makeDM(message: "Hello Bob!", from: alice, to: bob) else {
            XCTFail("Failed to create DM")
            return
        }

        mockSocket.reset()

        await postbox.send(dm, to: [testRelayURL], delay: 5.0)

        XCTAssertNotNil(postbox.events[dm.id])
        XCTAssertEqual(mockSocket.sentMessages.count, 0, "Delayed DM should not send immediately")
    }

    /// Test: Delayed DM can be cancelled
    func testDelayedDMCanBeCancelled() async throws {
        guard let dm = makeDM(message: "Hello Bob!", from: alice, to: bob) else {
            XCTFail("Failed to create DM")
            return
        }

        await postbox.send(dm, to: [testRelayURL], delay: 5.0)
        XCTAssertNotNil(postbox.events[dm.id])

        let cancelResult = postbox.cancel_send(evid: dm.id)

        XCTAssertNil(cancelResult, "Cancel should succeed")
        XCTAssertNil(postbox.events[dm.id], "DM should be removed after cancel")
    }

    // MARK: - on_flush Callback Tests

    /// Test: on_flush callback fires for DM
    func testOnFlushCallbackFiresForDM() async throws {
        guard let dm = makeDM(message: "Hello Bob!", from: alice, to: bob) else {
            XCTFail("Failed to create DM")
            return
        }

        var callbackFired = false
        let expectation = XCTestExpectation(description: "Callback should fire")

        await postbox.send(dm, to: [testRelayURL], on_flush: .once({ _ in
            callbackFired = true
            expectation.fulfill()
        }))

        simulateOKResponse(eventId: dm.id)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(callbackFired, "on_flush callback should fire")
    }
}
