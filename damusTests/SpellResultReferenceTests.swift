//
//  SpellResultReferenceTests.swift
//  damusTests
//
//  Tests for SpellResultReference extraction from spell feed results.
//

import XCTest
@testable import damus

final class SpellResultReferenceTests: XCTestCase {

    // MARK: - Reaction (kind:7) reference extraction

    func test_reaction_extracts_referenced_note_id() {
        // kind:7 reaction with e-tag referencing a note
        let targetNoteId = test_note.id
        let ev = NostrEvent(
            content: "+",
            keypair: test_keypair,
            kind: 7,
            tags: [["e", targetNoteId.hex()], ["p", test_pubkey.hex()]]
        )!

        let ref = SpellResultReference.extract(from: ev)

        guard case .reaction(let refId, let reactorPubkey, let emoji) = ref else {
            XCTFail("Expected .reaction, got \(ref)")
            return
        }

        XCTAssertEqual(refId, targetNoteId)
        XCTAssertEqual(reactorPubkey, test_keypair.pubkey)
        XCTAssertEqual(emoji, "❤️")
    }

    func test_reaction_uses_last_e_tag() {
        // NIP-25: the last e-tag is the event being reacted to
        let firstId = test_note.id
        let secondNote = NostrEvent(
            content: "second note",
            keypair: test_keypair,
            kind: 1,
            tags: []
        )!
        let lastId = secondNote.id

        let ev = NostrEvent(
            content: "🔥",
            keypair: test_keypair,
            kind: 7,
            tags: [["e", firstId.hex()], ["e", lastId.hex()]]
        )!

        let ref = SpellResultReference.extract(from: ev)

        guard case .reaction(let refId, _, let emoji) = ref else {
            XCTFail("Expected .reaction")
            return
        }

        XCTAssertEqual(refId, lastId)
        XCTAssertEqual(emoji, "🔥")
    }

    func test_reaction_custom_emoji() {
        let ev = NostrEvent(
            content: "🤙",
            keypair: test_keypair,
            kind: 7,
            tags: [["e", test_note.id.hex()]]
        )!

        let ref = SpellResultReference.extract(from: ev)

        guard case .reaction(_, _, let emoji) = ref else {
            XCTFail("Expected .reaction")
            return
        }

        XCTAssertEqual(emoji, "🤙")
    }

    func test_reaction_minus_emoji() {
        let ev = NostrEvent(
            content: "-",
            keypair: test_keypair,
            kind: 7,
            tags: [["e", test_note.id.hex()]]
        )!

        let ref = SpellResultReference.extract(from: ev)

        guard case .reaction(_, _, let emoji) = ref else {
            XCTFail("Expected .reaction")
            return
        }

        XCTAssertEqual(emoji, "👎")
    }

    func test_reaction_without_e_tag_falls_back_to_direct() {
        let ev = NostrEvent(
            content: "+",
            keypair: test_keypair,
            kind: 7,
            tags: [["p", test_pubkey.hex()]]
        )!

        let ref = SpellResultReference.extract(from: ev)

        XCTAssertEqual(ref, .directEvent)
    }

    // MARK: - Zap (kind:9735) reference extraction

    func test_zap_extracts_referenced_note_id() {
        let targetNoteId = test_note.id
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 9735,
            tags: [
                ["e", targetNoteId.hex()],
                ["p", test_pubkey.hex()]
            ]
        )!

        let ref = SpellResultReference.extract(from: ev)

        guard case .zap(let refId, _, _) = ref else {
            XCTFail("Expected .zap, got \(ref)")
            return
        }

        XCTAssertEqual(refId, targetNoteId)
    }

    func test_zap_without_e_tag_falls_back_to_direct() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 9735,
            tags: [["p", test_pubkey.hex()]]
        )!

        let ref = SpellResultReference.extract(from: ev)

        XCTAssertEqual(ref, .directEvent)
    }

    func test_zap_sender_defaults_to_event_pubkey_without_description() {
        // Without a description tag, can't extract the zap request,
        // so sender defaults to the event pubkey
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 9735,
            tags: [["e", test_note.id.hex()]]
        )!

        let ref = SpellResultReference.extract(from: ev)

        guard case .zap(_, let senderPubkey, _) = ref else {
            XCTFail("Expected .zap")
            return
        }

        XCTAssertEqual(senderPubkey, test_keypair.pubkey)
    }

    // MARK: - Non-reference kinds

    func test_text_note_is_direct_event() {
        let ev = NostrEvent(
            content: "hello world",
            keypair: test_keypair,
            kind: 1,
            tags: []
        )!

        let ref = SpellResultReference.extract(from: ev)

        XCTAssertEqual(ref, .directEvent)
    }

    func test_repost_is_direct_event() {
        // Reposts are handled by EventView's existing repost logic,
        // not by SpellResultReference
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 6,
            tags: [["e", test_note.id.hex()]]
        )!

        let ref = SpellResultReference.extract(from: ev)

        XCTAssertEqual(ref, .directEvent)
    }

    func test_longform_is_direct_event() {
        let ev = NostrEvent(
            content: "# My Article",
            keypair: test_keypair,
            kind: 30023,
            tags: []
        )!

        let ref = SpellResultReference.extract(from: ev)

        XCTAssertEqual(ref, .directEvent)
    }
}
