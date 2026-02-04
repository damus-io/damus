//
//  NIP17Tests.swift
//  damusTests
//
//  Tests for NIP-17 Private Direct Messages implementation.
//
//  NIP-17 message structure: rumor (kind 14) → seal (kind 13) → gift_wrap (kind 1059)
//

import XCTest
@testable import damus

final class NIP17Tests: XCTestCase {

    // MARK: - Test Keypairs

    /// Alice's keypair for testing
    var alice: FullKeypair {
        let sec = Privkey(hex: "494c680d20f202807a116a6915815bd76a27d62802e7585806f6a2e034cb5cdb")!
        return FullKeypair(privkey: sec)!
    }

    /// Bob's keypair for testing
    var bob: FullKeypair {
        let sec = Privkey(hex: "aa8920b05b4bd5c79fce46868ed5ebc82bdb91b211850b14541bfbd13953cfef")!
        return FullKeypair(privkey: sec)!
    }

    // MARK: - Message Creation Tests

    /// Test that createMessage returns two gift wraps (recipient + sender)
    func testCreateMessageReturnsTwoWraps() throws {
        let content = "Hello Bob!"

        let result = NIP17.createMessage(
            content: content,
            to: bob.pubkey,
            from: alice
        )

        XCTAssertNotNil(result, "createMessage should return a result")

        let (recipientWrap, senderWrap) = result!

        // Both should be kind 1059 (gift_wrap)
        XCTAssertEqual(recipientWrap.kind, NostrKind.gift_wrap.rawValue)
        XCTAssertEqual(senderWrap.kind, NostrKind.gift_wrap.rawValue)

        // Recipient wrap should have Bob's pubkey in p-tag
        let recipientPTag = recipientWrap.tags.first { $0.count >= 2 && $0[0].string() == "p" }
        XCTAssertNotNil(recipientPTag)
        XCTAssertEqual(recipientPTag?[1].string(), bob.pubkey.hex())

        // Sender wrap should have Alice's pubkey in p-tag (self-wrap)
        let senderPTag = senderWrap.tags.first { $0.count >= 2 && $0[0].string() == "p" }
        XCTAssertNotNil(senderPTag)
        XCTAssertEqual(senderPTag?[1].string(), alice.pubkey.hex())
    }

    /// Test that gift wrap uses ephemeral key (not sender's key)
    func testGiftWrapUsesEphemeralKey() throws {
        let result = NIP17.createMessage(
            content: "Secret message",
            to: bob.pubkey,
            from: alice
        )

        let (recipientWrap, _) = result!

        // Gift wrap pubkey should NOT be Alice's pubkey (should be ephemeral)
        XCTAssertNotEqual(recipientWrap.pubkey, alice.pubkey,
            "Gift wrap should use ephemeral key, not sender's key")
    }

    /// Test that timestamp is randomized (within 2 days in past)
    func testTimestampRandomization() throws {
        let now = UInt32(Date().timeIntervalSince1970)
        let twoDaysAgo = now - (2 * 24 * 60 * 60)

        // Create multiple messages to check randomization
        var timestamps: [UInt32] = []
        for _ in 0..<5 {
            let result = NIP17.createMessage(
                content: "Test",
                to: bob.pubkey,
                from: alice
            )
            if let (wrap, _) = result {
                timestamps.append(wrap.created_at)
            }
        }

        // All timestamps should be in range [now - 2 days, now]
        for ts in timestamps {
            XCTAssertGreaterThanOrEqual(ts, twoDaysAgo,
                "Timestamp should not be more than 2 days in the past")
            XCTAssertLessThanOrEqual(ts, now + 60, // Allow 60s buffer for test execution
                "Timestamp should not be in the future")
        }

        // At least some timestamps should differ (randomization check)
        // Note: There's a small chance all 5 could be the same, but very unlikely
        let uniqueTimestamps = Set(timestamps)
        XCTAssertGreaterThan(uniqueTimestamps.count, 1,
            "Timestamps should be randomized (got all same values)")
    }

    // MARK: - Unwrap Tests

    /// Test full wrap/unwrap round trip
    func testWrapUnwrapRoundTrip() throws {
        let originalContent = "Hello Bob, this is a secret message!"

        // Alice creates message for Bob
        let result = NIP17.createMessage(
            content: originalContent,
            to: bob.pubkey,
            from: alice
        )

        let (recipientWrap, _) = result!

        // Bob unwraps the message
        let unwrapped = NIP17.unwrap(
            giftWrap: recipientWrap,
            recipientKeypair: bob
        )

        XCTAssertNotNil(unwrapped, "Bob should be able to unwrap the message")

        // Verify the unwrapped rumor
        XCTAssertEqual(unwrapped!.kind, NostrKind.dm_chat.rawValue,
            "Unwrapped event should be kind 14 (dm_chat)")
        XCTAssertEqual(unwrapped!.content, originalContent,
            "Unwrapped content should match original")
    }

    /// Test sender can unwrap their own self-wrap
    func testSenderCanUnwrapSelfWrap() throws {
        let originalContent = "Message I sent"

        let result = NIP17.createMessage(
            content: originalContent,
            to: bob.pubkey,
            from: alice
        )

        let (_, senderWrap) = result!

        // Alice unwraps her self-wrap
        let unwrapped = NIP17.unwrap(
            giftWrap: senderWrap,
            recipientKeypair: alice
        )

        XCTAssertNotNil(unwrapped, "Sender should be able to unwrap self-wrap")
        XCTAssertEqual(unwrapped!.content, originalContent)
    }

    /// Test that wrong recipient cannot unwrap
    func testWrongRecipientCannotUnwrap() throws {
        // Alice sends to Bob
        let result = NIP17.createMessage(
            content: "For Bob only",
            to: bob.pubkey,
            from: alice
        )

        let (recipientWrap, _) = result!

        // Create a third party (Charlie)
        let charliePrivkey = Privkey(hex: "4c79130952c9c3b017dad62f37f285853a9c53f2a1184d94594f5b860f30b5a5")!
        let charlie = FullKeypair(privkey: charliePrivkey)!

        // Charlie tries to unwrap (should fail)
        let unwrapped = NIP17.unwrap(
            giftWrap: recipientWrap,
            recipientKeypair: charlie
        )

        XCTAssertNil(unwrapped, "Wrong recipient should not be able to unwrap")
    }

    /// Test unwrap rejects non-gift-wrap events
    func testUnwrapRejectsNonGiftWrap() throws {
        // Create a regular kind 1 event
        let regularEvent = NostrEvent(
            content: "Regular note",
            keypair: alice.to_keypair(),
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        let unwrapped = NIP17.unwrap(
            giftWrap: regularEvent,
            recipientKeypair: bob
        )

        XCTAssertNil(unwrapped, "Should reject non-gift-wrap events")
    }

    // MARK: - Reply Tag Tests

    /// Test that reply-to tag is included when specified
    func testReplyTagIncluded() throws {
        let replyToId = NoteId(hex: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")!

        let result = NIP17.createMessage(
            content: "This is a reply",
            to: bob.pubkey,
            from: alice,
            replyTo: replyToId
        )

        let (recipientWrap, _) = result!

        // Unwrap to check the rumor
        let unwrapped = NIP17.unwrap(
            giftWrap: recipientWrap,
            recipientKeypair: bob
        )!

        // Check for e-tag with reply marker
        let eTag = unwrapped.tags.first { $0.count >= 4 && $0[0].string() == "e" && $0[3].string() == "reply" }
        XCTAssertNotNil(eTag, "Reply tag should be present")
        XCTAssertEqual(eTag?[1].string(), replyToId.hex())
    }

    // MARK: - Kind Constant Tests

    /// Verify NIP-17 kind constants are correct per spec
    func testKindConstants() {
        XCTAssertEqual(NostrKind.seal.rawValue, 13)
        XCTAssertEqual(NostrKind.dm_chat.rawValue, 14)
        XCTAssertEqual(NostrKind.gift_wrap.rawValue, 1059)
        XCTAssertEqual(NostrKind.dm_relay_list.rawValue, 10050)
    }

    // MARK: - Edge Cases

    /// Test empty message content
    func testEmptyContent() throws {
        let result = NIP17.createMessage(
            content: "",
            to: bob.pubkey,
            from: alice
        )

        // Empty content should still work (NIP-17 doesn't forbid it)
        XCTAssertNotNil(result)

        let (recipientWrap, _) = result!
        let unwrapped = NIP17.unwrap(giftWrap: recipientWrap, recipientKeypair: bob)

        XCTAssertNotNil(unwrapped)
        XCTAssertEqual(unwrapped!.content, "")
    }

    /// Test Unicode content
    func testUnicodeContent() throws {
        let content = "Hello 👋 こんにちは 🎉 مرحبا"

        let result = NIP17.createMessage(
            content: content,
            to: bob.pubkey,
            from: alice
        )

        let (recipientWrap, _) = result!
        let unwrapped = NIP17.unwrap(giftWrap: recipientWrap, recipientKeypair: bob)

        XCTAssertNotNil(unwrapped)
        XCTAssertEqual(unwrapped!.content, content)
    }

    /// Test long message content
    func testLongContent() throws {
        // Create a ~10KB message
        let content = String(repeating: "A", count: 10000)

        let result = NIP17.createMessage(
            content: content,
            to: bob.pubkey,
            from: alice
        )

        XCTAssertNotNil(result)

        let (recipientWrap, _) = result!
        let unwrapped = NIP17.unwrap(giftWrap: recipientWrap, recipientKeypair: bob)

        XCTAssertNotNil(unwrapped)
        XCTAssertEqual(unwrapped!.content, content)
    }

    // MARK: - DM Relay List (Kind 10050) Tests

    /// Test creating a DM relay list event
    func testCreateDMRelayList() throws {
        let relays = [
            RelayURL("wss://relay.damus.io")!,
            RelayURL("wss://nos.lol")!,
            RelayURL("wss://nostr.wine")!
        ]

        let event = NIP17.createDMRelayList(relays: relays, keypair: alice.to_keypair())

        XCTAssertNotNil(event, "Should create DM relay list event")
        XCTAssertEqual(event!.kind, NostrKind.dm_relay_list.rawValue,
            "Should be kind 10050")

        // Verify relay tags
        let relayTags = event!.tags.filter { $0.count >= 2 && $0[0].string() == "relay" }
        XCTAssertEqual(relayTags.count, 3, "Should have 3 relay tags")
    }

    /// Test parsing a DM relay list event
    func testParseDMRelayList() throws {
        let relays = [
            RelayURL("wss://relay.damus.io")!,
            RelayURL("wss://nos.lol")!
        ]

        guard let event = NIP17.createDMRelayList(relays: relays, keypair: alice.to_keypair()) else {
            XCTFail("Failed to create DM relay list")
            return
        }

        let parsed = NIP17.parseDMRelayList(event: event)

        XCTAssertEqual(parsed.count, 2, "Should parse 2 relays")
        XCTAssertTrue(parsed.contains(where: { $0.absoluteString == "wss://relay.damus.io" }))
        XCTAssertTrue(parsed.contains(where: { $0.absoluteString == "wss://nos.lol" }))
    }

    /// Test parsing empty DM relay list returns empty array
    func testParseDMRelayListEmpty() throws {
        // Create event with no relay tags
        let event = NostrEvent(
            content: "",
            keypair: alice.to_keypair(),
            kind: NostrKind.dm_relay_list.rawValue,
            tags: []
        )!

        let parsed = NIP17.parseDMRelayList(event: event)

        XCTAssertTrue(parsed.isEmpty, "Should return empty array for event with no relay tags")
    }

    /// Test parsing wrong kind returns empty array
    func testParseDMRelayListWrongKind() throws {
        let event = NostrEvent(
            content: "",
            keypair: alice.to_keypair(),
            kind: NostrKind.text.rawValue, // Wrong kind
            tags: [["relay", "wss://relay.damus.io"]]
        )!

        let parsed = NIP17.parseDMRelayList(event: event)

        XCTAssertTrue(parsed.isEmpty, "Should return empty for wrong kind")
    }

    // MARK: - Error Path Tests

    /// Test unwrap with empty content fails gracefully
    func testUnwrapEmptyContentFails() throws {
        // Create gift wrap with empty content (invalid)
        let emptyWrap = NostrEvent(
            content: "",
            keypair: alice.to_keypair(),
            kind: NostrKind.gift_wrap.rawValue,
            tags: [["p", bob.pubkey.hex()]]
        )!

        let result = NIP17.unwrap(giftWrap: emptyWrap, recipientKeypair: bob)

        XCTAssertNil(result, "Should fail to unwrap empty content")
    }

    /// Test unwrap with malformed content fails gracefully
    func testUnwrapMalformedContentFails() throws {
        // Create gift wrap with invalid encrypted content
        let badWrap = NostrEvent(
            content: "not-valid-encrypted-content",
            keypair: alice.to_keypair(),
            kind: NostrKind.gift_wrap.rawValue,
            tags: [["p", bob.pubkey.hex()]]
        )!

        let result = NIP17.unwrap(giftWrap: badWrap, recipientKeypair: bob)

        XCTAssertNil(result, "Should fail to unwrap malformed content")
    }

    /// Test createMessage with empty content still works
    func testCreateMessageEmptyContent() throws {
        let result = NIP17.createMessage(
            content: "",
            to: bob.pubkey,
            from: alice
        )

        XCTAssertNotNil(result, "Should create message even with empty content")

        let (recipientWrap, _) = result!
        let unwrapped = NIP17.unwrap(giftWrap: recipientWrap, recipientKeypair: bob)

        XCTAssertNotNil(unwrapped)
        XCTAssertEqual(unwrapped!.content, "")
    }

    // MARK: - Integration Test Notes
    //
    // The following scenarios require integration tests with mocked RelayPool:
    // - ensureConnected() behavior with successful connections
    // - ensureConnected() behavior with connection failures
    // - ensureConnected() timeout handling
    // - Ephemeral relay cleanup after sending
    //
    // These tests are not included here because they require network mocking
    // infrastructure that doesn't currently exist in the test suite.
}
