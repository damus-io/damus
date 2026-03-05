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
