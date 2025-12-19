//
//  NIP19Tests.swift
//  damusTests
//
//  Created by William Casarin on 2023-04-09.
//

import XCTest
@testable import damus

final class NIP19Tests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /*
    func test_parse_nprofile() throws {
        let res = parse_note_content(content: .content("nostr:nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p")).blocks
        XCTAssertEqual(res.count, 1)
        let expected_ref = ReferencedId(ref_id: "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", relay_id: "wss://r.x.com", key: "p")
        let expected_mention = Mention(index: nil, type: .pubkey, ref: expected_ref)
        XCTAssertEqual(res[0], .mention(expected_mention))
    }
     */

    func test_parse_npub() throws {
        let res = parse_note_content(content: .content("nostr:npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg ",nil))!.blocks
        XCTAssertEqual(res.count, 2)
        let expected_ref = Pubkey(hex: "7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e")!
        let expected_mention: Mention<MentionRef> = .any(.init(bech32_str: "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg")!)
        XCTAssertEqual(res[0], .mention(expected_mention))
    }
    
    func test_parse_note() throws {
        let res = parse_note_content(content: .content(" nostr:note1s4p70596lv50x0zftuses32t6ck8x6wgd4edwacyetfxwns2jtysux7vep",nil))!.blocks
        XCTAssertEqual(res.count, 2)
        let note_id = NoteId(hex:"8543e7d0bafb28f33c495f2198454bd62c7369c86d72d77704cad2674e0a92c9")!
        XCTAssertEqual(res[1], .mention(.any(.note(note_id))))
    }
    
    func test_mention_with_adjacent() throws {
        let res = parse_note_content(content: .content(" nostr:note1s4p70596lv50x0zftuses32t6ck8x6wgd4edwacyetfxwns2jtysux7vep?",nil))!.blocks
        XCTAssertEqual(res.count, 3)
        let note_id = NoteId(hex: "8543e7d0bafb28f33c495f2198454bd62c7369c86d72d77704cad2674e0a92c9")!
        XCTAssertEqual(res[0], .text(" "))
        XCTAssertEqual(res[1], .mention(.any(.note(note_id))))
        XCTAssertEqual(res[2], .text("?"))
    }

    // MARK: - Longform Markdown Preprocessing Tests

    func test_preprocess_nprofile_in_markdown() throws {
        let profiles = test_damus_state.profiles
        let nprofile = "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
        let markdown = "Check out nostr:\(nprofile) for more info."
        let result = preprocessNostrLinksInMarkdown(markdown, profiles: profiles)

        XCTAssertTrue(result.contains("](damus:nostr:\(nprofile))"), "nprofile should be converted to markdown link")
        XCTAssertFalse(result.contains("nostr:\(nprofile) "), "Bare nostr URI should be replaced")
    }

    func test_preprocess_npub_in_markdown() throws {
        let profiles = test_damus_state.profiles
        let npub = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"
        let markdown = "Follow nostr:\(npub) on nostr!"
        let result = preprocessNostrLinksInMarkdown(markdown, profiles: profiles)

        XCTAssertTrue(result.contains("](damus:nostr:\(npub))"), "npub should be converted to markdown link")
    }

    func test_preprocess_note_in_markdown() throws {
        let profiles = test_damus_state.profiles
        let note = "note1s4p70596lv50x0zftuses32t6ck8x6wgd4edwacyetfxwns2jtysux7vep"
        let markdown = "See this post: nostr:\(note)"
        let result = preprocessNostrLinksInMarkdown(markdown, profiles: profiles)

        XCTAssertTrue(result.contains("](damus:nostr:\(note))"), "note should be converted to markdown link")
        XCTAssertTrue(result.contains("[@"), "note mention should have @ prefix")
    }

    func test_preprocess_nevent_in_markdown() throws {
        let profiles = test_damus_state.profiles
        let nevent = "nevent1qqs9tcwc9dx5dqun6u4sxfkgkuy6p0znk2slqjjjlctxsjffxr98u0qpz3mhxue69uhhyetvv9ujuerpd46hxtnfdufzkeuj"
        let markdown = "Check this event: nostr:\(nevent)"
        let result = preprocessNostrLinksInMarkdown(markdown, profiles: profiles)

        XCTAssertTrue(result.contains("](damus:nostr:\(nevent))"), "nevent should be converted to markdown link")
        XCTAssertTrue(result.contains("[@"), "nevent mention should have @ prefix")
    }

    func test_preprocess_does_not_double_process_existing_links() throws {
        let profiles = test_damus_state.profiles
        let npub = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"
        let markdown = "Already a link: [@someone](damus:nostr:\(npub))"
        let result = preprocessNostrLinksInMarkdown(markdown, profiles: profiles)

        XCTAssertEqual(result, markdown, "Existing markdown links should not be double-processed")
    }

    func test_preprocess_multiple_nostr_uris() throws {
        let profiles = test_damus_state.profiles
        let npub = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"
        let note = "note1s4p70596lv50x0zftuses32t6ck8x6wgd4edwacyetfxwns2jtysux7vep"
        let markdown = "User nostr:\(npub) posted nostr:\(note)"
        let result = preprocessNostrLinksInMarkdown(markdown, profiles: profiles)

        XCTAssertTrue(result.contains("](damus:nostr:\(npub))"), "First URI should be converted")
        XCTAssertTrue(result.contains("](damus:nostr:\(note))"), "Second URI should be converted")
    }

    func test_preprocess_plain_text_unchanged() throws {
        let profiles = test_damus_state.profiles
        let markdown = "This is just plain text without any nostr links."
        let result = preprocessNostrLinksInMarkdown(markdown, profiles: profiles)

        XCTAssertEqual(result, markdown, "Plain text should remain unchanged")
    }

    // MARK: - Bare Bech32 Entity Tests (without nostr: prefix)

    func test_preprocess_bare_npub_without_nostr_prefix() throws {
        let profiles = test_damus_state.profiles
        let npub = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"
        let markdown = "Check out \(npub) for updates."
        let result = preprocessNostrLinksInMarkdown(markdown, profiles: profiles)

        XCTAssertTrue(result.contains("](damus:nostr:\(npub))"), "Bare npub should be converted to markdown link")
        XCTAssertFalse(result.contains(" \(npub) "), "Bare npub should be replaced")
    }

    func test_preprocess_bare_nprofile_without_nostr_prefix() throws {
        let profiles = test_damus_state.profiles
        let nprofile = "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
        let markdown = "Follow \(nprofile) on nostr!"
        let result = preprocessNostrLinksInMarkdown(markdown, profiles: profiles)

        XCTAssertTrue(result.contains("](damus:nostr:\(nprofile))"), "Bare nprofile should be converted to markdown link")
    }

}
