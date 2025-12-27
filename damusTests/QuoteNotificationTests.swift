//
//  QuoteNotificationTests.swift
//  damusTests
//
//  Tests for quote notification detection to ensure third-party client
//  quotes are properly identified as notifications.
//
//  Background:
//  Per NIP-18, quote posts use q tags: ["q", "<event-id>", "<relay-url>", "<pubkey>"]
//  Third-party clients may not include a separate p tag for the quoted note's author.
//  These tests verify that:
//  1. Standard p-tag notifications still work
//  2. Quote notifications (q-tag only) are properly detected
//  3. Our note ID tracking works correctly
//

import XCTest
@testable import damus

final class QuoteNotificationTests: XCTestCase {

    /// Create a simple keypair for testing
    private func makeTestKeypair(seed: UInt8) -> FullKeypair? {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[31] = seed
        let privkey = Privkey(Data(bytes))
        guard let pubkey = privkey_to_pubkey(privkey: privkey) else {
            return nil
        }
        return FullKeypair(pubkey: pubkey, privkey: privkey)
    }

    /// Tests that event_has_our_pubkey correctly identifies events with our pubkey in p tags
    func testEventHasOurPubkey() throws {
        guard let ourKeypair = makeTestKeypair(seed: 1) else {
            XCTFail("Could not create test keypair")
            return
        }
        guard let otherKeypair = makeTestKeypair(seed: 2) else {
            XCTFail("Could not create other keypair")
            return
        }

        // Create an event that mentions our pubkey
        let eventWithPubkey = """
        {"id":"a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd","pubkey":"\(otherKeypair.pubkey.hex())","created_at":1700000000,"kind":1,"tags":[["p","\(ourKeypair.pubkey.hex())"]],"content":"Hello @user","sig":"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"}
        """

        guard let note = NdbNote.owned_from_json(json: eventWithPubkey) else {
            XCTFail("Could not parse event with pubkey")
            return
        }

        let result = event_has_our_pubkey(note, our_pubkey: ourKeypair.pubkey)
        XCTAssertTrue(result, "event_has_our_pubkey should return true when our pubkey is in a p tag")
    }

    /// Tests that event_has_our_pubkey returns false when our pubkey is not present
    func testEventDoesNotHaveOurPubkey() throws {
        guard let ourKeypair = makeTestKeypair(seed: 1) else {
            XCTFail("Could not create test keypair")
            return
        }
        guard let otherKeypair = makeTestKeypair(seed: 2) else {
            XCTFail("Could not create other keypair")
            return
        }

        // Create an event without our pubkey
        let eventWithoutPubkey = """
        {"id":"a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd","pubkey":"\(otherKeypair.pubkey.hex())","created_at":1700000000,"kind":1,"tags":[["t","nostr"]],"content":"Hello world","sig":"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"}
        """

        guard let note = NdbNote.owned_from_json(json: eventWithoutPubkey) else {
            XCTFail("Could not parse event")
            return
        }

        let result = event_has_our_pubkey(note, our_pubkey: ourKeypair.pubkey)
        XCTAssertFalse(result, "event_has_our_pubkey should return false when our pubkey is not present")
    }

    /// Tests that quote events with q tags pointing to our note IDs can be detected
    func testQuoteEventReferencesOurNote() throws {
        guard let ourKeypair = makeTestKeypair(seed: 1) else {
            XCTFail("Could not create test keypair")
            return
        }
        guard let otherKeypair = makeTestKeypair(seed: 2) else {
            XCTFail("Could not create other keypair")
            return
        }

        // Simulate our note ID
        let ourNoteId = NoteId(hex: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")!

        // Create a quote event that references our note via q tag only (no p tag)
        let quoteEvent = """
        {"id":"fedcba0987654321fedcba0987654321fedcba0987654321fedcba09876543ab","pubkey":"\(otherKeypair.pubkey.hex())","created_at":1700000000,"kind":1,"tags":[["q","\(ourNoteId.hex())","wss://relay.example.com","\(ourKeypair.pubkey.hex())"]],"content":"Nice quote!","sig":"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"}
        """

        guard let note = NdbNote.owned_from_json(json: quoteEvent) else {
            XCTFail("Could not parse quote event")
            return
        }

        // Create a set of our note IDs (simulating what HomeModel tracks)
        let ourNoteIds: Set<NoteId> = [ourNoteId]

        // Check if the quote references one of our notes
        let quotesOurNote = note.referenced_quote_ids.contains { ourNoteIds.contains($0.note_id) }
        XCTAssertTrue(quotesOurNote, "Quote event should be detected as quoting our note")

        // Verify this event does NOT have our pubkey in p tags (the scenario we're fixing)
        let hasOurPubkey = event_has_our_pubkey(note, our_pubkey: ourKeypair.pubkey)
        XCTAssertFalse(hasOurPubkey, "Quote event should not have our pubkey in p tag (testing the edge case)")
    }

    /// Tests that quote events NOT referencing our notes are not matched
    func testQuoteEventDoesNotReferenceOurNote() throws {
        guard let ourKeypair = makeTestKeypair(seed: 1) else {
            XCTFail("Could not create test keypair")
            return
        }
        guard let otherKeypair = makeTestKeypair(seed: 2) else {
            XCTFail("Could not create other keypair")
            return
        }

        // Our note ID
        let ourNoteId = NoteId(hex: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")!

        // Someone else's note ID that the quote references
        let otherNoteId = NoteId(hex: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")!

        // Create a quote event that references someone else's note
        let quoteEvent = """
        {"id":"fedcba0987654321fedcba0987654321fedcba0987654321fedcba09876543ab","pubkey":"\(otherKeypair.pubkey.hex())","created_at":1700000000,"kind":1,"tags":[["q","\(otherNoteId.hex())","wss://relay.example.com","\(otherKeypair.pubkey.hex())"]],"content":"Nice quote!","sig":"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"}
        """

        guard let note = NdbNote.owned_from_json(json: quoteEvent) else {
            XCTFail("Could not parse quote event")
            return
        }

        // Our note IDs set
        let ourNoteIds: Set<NoteId> = [ourNoteId]

        // Check if the quote references one of our notes
        let quotesOurNote = note.referenced_quote_ids.contains { ourNoteIds.contains($0.note_id) }
        XCTAssertFalse(quotesOurNote, "Quote event should NOT be detected as quoting our note")
    }

    /// Tests the combined notification relevance check (pubkey OR quote)
    func testCombinedNotificationRelevanceCheck() throws {
        guard let ourKeypair = makeTestKeypair(seed: 1) else {
            XCTFail("Could not create test keypair")
            return
        }
        guard let otherKeypair = makeTestKeypair(seed: 2) else {
            XCTFail("Could not create other keypair")
            return
        }

        let ourNoteId = NoteId(hex: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")!
        let ourNoteIds: Set<NoteId> = [ourNoteId]

        // Helper function mimicking the validation in handle_notification
        func isRelevantNotification(_ note: NdbNote) -> Bool {
            let hasOurPubkey = event_has_our_pubkey(note, our_pubkey: ourKeypair.pubkey)
            let quotesOurNote = note.referenced_quote_ids.contains { ourNoteIds.contains($0.note_id) }
            return hasOurPubkey || quotesOurNote
        }

        // Test 1: Event with p tag mentioning us (traditional notification)
        let eventWithPtag = """
        {"id":"aaaa567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","pubkey":"\(otherKeypair.pubkey.hex())","created_at":1700000000,"kind":1,"tags":[["p","\(ourKeypair.pubkey.hex())"]],"content":"Hey!","sig":"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"}
        """
        guard let noteWithPtag = NdbNote.owned_from_json(json: eventWithPtag) else {
            XCTFail("Could not parse event with p tag")
            return
        }
        XCTAssertTrue(isRelevantNotification(noteWithPtag), "Event with p tag should be relevant")

        // Test 2: Event with q tag quoting our note (third-party client quote)
        let eventWithQtag = """
        {"id":"bbbb567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","pubkey":"\(otherKeypair.pubkey.hex())","created_at":1700000000,"kind":1,"tags":[["q","\(ourNoteId.hex())","wss://relay.example.com","\(ourKeypair.pubkey.hex())"]],"content":"Quote!","sig":"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"}
        """
        guard let noteWithQtag = NdbNote.owned_from_json(json: eventWithQtag) else {
            XCTFail("Could not parse event with q tag")
            return
        }
        XCTAssertTrue(isRelevantNotification(noteWithQtag), "Event with q tag quoting our note should be relevant")

        // Test 3: Event with both p and q tags (Damus-style quote)
        let eventWithBothTags = """
        {"id":"cccc567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","pubkey":"\(otherKeypair.pubkey.hex())","created_at":1700000000,"kind":1,"tags":[["q","\(ourNoteId.hex())","wss://relay.example.com","\(ourKeypair.pubkey.hex())"],["p","\(ourKeypair.pubkey.hex())"]],"content":"Damus quote!","sig":"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"}
        """
        guard let noteWithBothTags = NdbNote.owned_from_json(json: eventWithBothTags) else {
            XCTFail("Could not parse event with both tags")
            return
        }
        XCTAssertTrue(isRelevantNotification(noteWithBothTags), "Event with both p and q tags should be relevant")

        // Test 4: Event with neither our pubkey nor our note (should not be relevant)
        let unrelatedEvent = """
        {"id":"dddd567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","pubkey":"\(otherKeypair.pubkey.hex())","created_at":1700000000,"kind":1,"tags":[["t","nostr"]],"content":"Random post","sig":"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"}
        """
        guard let unrelatedNote = NdbNote.owned_from_json(json: unrelatedEvent) else {
            XCTFail("Could not parse unrelated event")
            return
        }
        XCTAssertFalse(isRelevantNotification(unrelatedNote), "Unrelated event should not be relevant")
    }
}
