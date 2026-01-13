//
//  CustomEmojiTests.swift
//  damusTests
//
//  Created for NIP-30 custom emoji support.
//

import XCTest
@testable import damus

final class CustomEmojiTests: XCTestCase {

    /// Tests parsing a single custom emoji tag from an event.
    func testParseCustomEmojiTag() throws {
        let json = """
        ["EVENT","test",{"id":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","pubkey":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","created_at":1682630000,"kind":1,"content":"Hello :soapbox:","tags":[["emoji","soapbox","https://example.com/emoji/soapbox.png"]],"sig":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"}]
        """

        guard let response = decode_nostr_event(txt: json),
              case .event(_, let event) = response else {
            XCTFail("Failed to decode event")
            return
        }

        let emojis = Array(event.referenced_custom_emojis)
        XCTAssertEqual(emojis.count, 1)
        XCTAssertEqual(emojis[0].shortcode, "soapbox")
        XCTAssertEqual(emojis[0].url.absoluteString, "https://example.com/emoji/soapbox.png")
    }

    /// Tests parsing multiple custom emoji tags from an event.
    func testParseMultipleCustomEmojiTags() throws {
        let json = """
        ["EVENT","test",{"id":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","pubkey":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","created_at":1682630000,"kind":1,"content":"Hello :gleasonator: :ablobcatrainbow: :disputed:","tags":[["emoji","ablobcatrainbow","https://example.com/emoji/ablobcatrainbow.png"],["emoji","disputed","https://example.com/emoji/disputed.png"],["emoji","gleasonator","https://example.com/emoji/gleasonator.png"]],"sig":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"}]
        """

        guard let response = decode_nostr_event(txt: json),
              case .event(_, let event) = response else {
            XCTFail("Failed to decode event")
            return
        }

        let emojis = Array(event.referenced_custom_emojis)
        XCTAssertEqual(emojis.count, 3)

        let shortcodes = Set(emojis.map { $0.shortcode })
        XCTAssertTrue(shortcodes.contains("ablobcatrainbow"))
        XCTAssertTrue(shortcodes.contains("disputed"))
        XCTAssertTrue(shortcodes.contains("gleasonator"))
    }

    /// Tests that events without emoji tags return empty.
    func testNoCustomEmojiTags() throws {
        let json = """
        ["EVENT","test",{"id":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","pubkey":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","created_at":1682630000,"kind":1,"content":"Hello world","tags":[["t","bitcoin"]],"sig":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"}]
        """

        guard let response = decode_nostr_event(txt: json),
              case .event(_, let event) = response else {
            XCTFail("Failed to decode event")
            return
        }

        let emojis = Array(event.referenced_custom_emojis)
        XCTAssertEqual(emojis.count, 0)
    }

    /// Tests that malformed emoji tags are skipped.
    func testMalformedEmojiTagsSkipped() throws {
        let json = """
        ["EVENT","test",{"id":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","pubkey":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","created_at":1682630000,"kind":1,"content":"Hello :valid:","tags":[["emoji","missing_url"],["emoji","valid","https://example.com/valid.png"],["emoji"]],"sig":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"}]
        """

        guard let response = decode_nostr_event(txt: json),
              case .event(_, let event) = response else {
            XCTFail("Failed to decode event")
            return
        }

        let emojis = Array(event.referenced_custom_emojis)
        XCTAssertEqual(emojis.count, 1)
        XCTAssertEqual(emojis[0].shortcode, "valid")
    }

    /// Tests CustomEmoji tag generation.
    func testCustomEmojiTagGeneration() throws {
        let emoji = CustomEmoji(shortcode: "test", url: URL(string: "https://example.com/test.png")!)
        let tag = emoji.tag

        XCTAssertEqual(tag.count, 3)
        XCTAssertEqual(tag[0], "emoji")
        XCTAssertEqual(tag[1], "test")
        XCTAssertEqual(tag[2], "https://example.com/test.png")
    }

    /// Tests CustomEmoji with kind 7 reaction event.
    func testCustomEmojiInReaction() throws {
        let json = """
        ["EVENT","test",{"id":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","pubkey":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","created_at":1682630000,"kind":7,"content":":dezh:","tags":[["emoji","dezh","https://example.com/dezh.svg"]],"sig":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"}]
        """

        guard let response = decode_nostr_event(txt: json),
              case .event(_, let event) = response else {
            XCTFail("Failed to decode event")
            return
        }

        XCTAssertEqual(event.kind, 7)

        let emojis = Array(event.referenced_custom_emojis)
        XCTAssertEqual(emojis.count, 1)
        XCTAssertEqual(emojis[0].shortcode, "dezh")
    }

    // MARK: - Emojify Function Tests

    /// Tests emojify_text with no emoji map returns original text.
    func testEmojifyNoEmojis() throws {
        let text = "Hello :world: test"
        let result = emojify_text(text, emojis: [:])

        XCTAssertEqual(result.attributed.description.contains("Hello :world: test"), true)
    }

    /// Tests emojify_text replaces matching shortcodes.
    func testEmojifyReplacesMatchingShortcodes() throws {
        let emoji = CustomEmoji(shortcode: "wave", url: URL(string: "https://example.com/wave.png")!)
        let emojiMap = ["wave": emoji]

        let text = "Hello :wave: there"
        let result = emojify_text(text, emojis: emojiMap)

        // Should have items for: "Hello ", emoji fallback, " there"
        XCTAssertEqual(result.items.count, 3)
    }

    /// Tests emojify_text ignores non-matching shortcodes.
    func testEmojifyIgnoresNonMatching() throws {
        let emoji = CustomEmoji(shortcode: "wave", url: URL(string: "https://example.com/wave.png")!)
        let emojiMap = ["wave": emoji]

        let text = "Hello :unknown: there"
        let result = emojify_text(text, emojis: emojiMap)

        // Non-matching shortcode should be left as-is
        XCTAssertEqual(result.attributed.description.contains(":unknown:"), true)
    }

    /// Tests emojify_text handles multiple shortcodes.
    func testEmojifyMultipleShortcodes() throws {
        let wave = CustomEmoji(shortcode: "wave", url: URL(string: "https://example.com/wave.png")!)
        let smile = CustomEmoji(shortcode: "smile", url: URL(string: "https://example.com/smile.png")!)
        let emojiMap = ["wave": wave, "smile": smile]

        let text = "Hello :wave: and :smile: today"
        let result = emojify_text(text, emojis: emojiMap)

        // Should have items for: "Hello ", wave, " and ", smile, " today"
        XCTAssertEqual(result.items.count, 5)
    }

    /// Tests build_custom_emoji_map creates correct mapping.
    func testBuildCustomEmojiMap() throws {
        let json = """
        ["EVENT","test",{"id":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","pubkey":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef","created_at":1682630000,"kind":1,"content":"Test :a: :b:","tags":[["emoji","a","https://example.com/a.png"],["emoji","b","https://example.com/b.png"]],"sig":"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"}]
        """

        guard let response = decode_nostr_event(txt: json),
              case .event(_, let event) = response else {
            XCTFail("Failed to decode event")
            return
        }

        let emojiMap = build_custom_emoji_map(event)

        XCTAssertEqual(emojiMap.count, 2)
        XCTAssertNotNil(emojiMap["a"])
        XCTAssertNotNil(emojiMap["b"])
        XCTAssertEqual(emojiMap["a"]?.url.absoluteString, "https://example.com/a.png")
    }

    /// Tests parsing with real production event JSON.
    func testRealProductionEvent() throws {
        let json = """
        ["EVENT","test",{"sig":"51b7a371657e91e24eb8ac9b50aa28ca1b41b207cde5148f945753c1c97d54f89cd5b706aadb402cfad1bece64ceb8efadc8670160838b39296e51cfc8bdefe8","kind":1,"tags":[["emoji","Zapchat","https://cdn.satellite.earth/307b087499ae5444de1033e62ac98db7261482c1531e741afad44a0f8f9871ee.png"],["emoji","chat","https://cdn.satellite.earth/f388f24d87d9d96076a53773c347a79767402d758edd3b2ac21da51db5ce6e73.png"],["emoji","zap","https://cdn.satellite.earth/514377b4d5dd035a58c4c574c29ff362e22997c542b7945fd9192f6ab8ecbcd7.png"],["emoji","community","https://cdn.satellite.earth/e4cff5b1e016c1fc740dfe8068728b2cd0391670c1fc733c4eda087a12a97a06.png"],["client","jumble"]],"pubkey":"a9434ee165ed01b286becfc2771ef1705d3537d051b387288898cc00d5c885be","content":"I'm looking for a good Community app name that, unlike :Zapchat: Zapchat, takes the focus away from :chat: Chat and :zap: Zaps and instead leans more towards a community clubhouse/castle/cabin where many content types live. \\n\\nIdeas are welcome  :community:","id":"e80a9d1e7d25f91e3c50df2ce8b1cceb665a3f72eb31cb3f207c630a5ecaec1c","created_at":1768212051}]
        """

        guard let response = decode_nostr_event(txt: json),
              case .event(_, let event) = response else {
            XCTFail("Failed to decode event")
            return
        }

        // Verify we can parse the emoji tags
        let emojis = Array(event.referenced_custom_emojis)
        print("Found \(emojis.count) emojis")
        for emoji in emojis {
            print("  - \(emoji.shortcode): \(emoji.url)")
        }

        XCTAssertEqual(emojis.count, 4, "Should find 4 emoji tags")

        let shortcodes = Set(emojis.map { $0.shortcode })
        XCTAssertTrue(shortcodes.contains("Zapchat"))
        XCTAssertTrue(shortcodes.contains("chat"))
        XCTAssertTrue(shortcodes.contains("zap"))
        XCTAssertTrue(shortcodes.contains("community"))

        // Test emoji map building
        let emojiMap = build_custom_emoji_map(event)
        XCTAssertEqual(emojiMap.count, 4)

        // Test emojify
        let result = emojify_text("Hello :Zapchat: world", emojis: emojiMap)
        XCTAssertEqual(result.items.count, 3, "Should have 3 items: text, emoji, text")
    }
}
