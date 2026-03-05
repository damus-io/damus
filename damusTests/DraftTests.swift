//
//  DraftTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2025-01-15

import XCTest
@testable import damus

class DraftTests: XCTestCase {
    func testRoundtripNIP37Draft() {
        let test_note =
                NostrEvent(
                    content: "Test",
                    keypair: test_keypair_full.to_keypair(),
                    createdAt: UInt32(Date().timeIntervalSince1970 - 100)
                )!
        let draft = try! NIP37Draft(unwrapped_note: test_note, draft_id: "test", keypair: test_keypair_full)!
        XCTAssertEqual(draft.unwrapped_note, test_note)
    }

    // MARK: - sanitizeNsecTokens tests

    /// Validates that a real nsec1 token is stripped from plain text, URL paths, and query strings.
    func testSanitizeNsecTokens_stripsValidNsec() {
        let nsec = bech32_privkey(test_seckey)
        XCTAssertFalse(sanitizeNsecTokens("My key is \(nsec) please help").contains(nsec))
        XCTAssertFalse(sanitizeNsecTokens("https://example.com/\(nsec)/info").contains(nsec))
        XCTAssertFalse(sanitizeNsecTokens("https://example.com?key=\(nsec)").contains(nsec))
    }

    /// Short or incidental "nsec1" substrings that don't form a valid key should be left alone.
    func testSanitizeNsecTokens_incidentalTextNotStripped() {
        let input = "The word nsec1 is not a key and nsec1abc is also not"
        XCTAssertEqual(sanitizeNsecTokens(input), input)
    }

    /// Other bech32 tokens (e.g. nevent1) must survive even when an nsec1 is stripped from the same string.
    func testSanitizeNsecTokens_preservesOtherBech32() {
        let nsec = bech32_privkey(test_seckey)
        let nevent = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm"
        let result = sanitizeNsecTokens("Event: nostr:\(nevent) key: \(nsec)")
        XCTAssertFalse(result.contains(nsec))
        XCTAssertTrue(result.contains(nevent))
    }

    // MARK: - C parser regression

    /// Regression: C parser previously converted damus.io URLs to BLOCK_MENTION_BECH32,
    /// causing garbled rendering when "Keep web link" was enabled.
    func testCParserDamusIOUrlNotConvertedToMention() {
        let npub = "npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m"
        guard let blocks = parse_post_blocks(content: "https://damus.io/\(npub)") else {
            XCTFail("Failed to parse content")
            return
        }
        let urlBlocks = blocks.blocks.filter { if case .url = $0 { return true }; return false }
        let mentionBlocks = blocks.blocks.filter { if case .mention = $0 { return true }; return false }
        XCTAssertEqual(urlBlocks.count, 1, "damus.io URL should be parsed as a URL block")
        XCTAssertEqual(mentionBlocks.count, 0, "damus.io URL should not be converted to a mention block")
    }
}
