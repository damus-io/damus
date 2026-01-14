//
//  LikeTests.swift
//  damusTests
//
//  Created by William Casarin on 2022-05-08.
//

import XCTest
@testable import damus

class LikeTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testLikeHasNotification() throws {
        let cindy = Pubkey(hex: "9d9181f0aea6500e1f360e07b9f37e25c72169b5158ae78df53f295272b6b71c")!
        let bob = Pubkey(hex: "218837fe8c94a66ae33af277bcbda45a0319e7726220cd76171b9dd1a468af91")!
        let liked = NostrEvent(content: "awesome #[0] post",
                               keypair: test_keypair,
                               tags: [cindy.tag, bob.tag])!
        let id = liked.id
        let like_ev = make_like_event(keypair: test_keypair_full, liked: liked, relayURL: nil)!

        XCTAssertTrue(like_ev.referenced_pubkeys.contains(test_keypair.pubkey))
        XCTAssertTrue(like_ev.referenced_pubkeys.contains(cindy))
        XCTAssertTrue(like_ev.referenced_pubkeys.contains(bob))
        XCTAssertEqual(like_ev.last_refid()!, id)
    }

    func testToReactionEmoji() {
        let liked = NostrEvent(content: "awesome #[0] post", keypair: test_keypair, tags: [["p", "cindy"], ["e", "bob"]])!

        let emptyReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "", relayURL: nil)!
        let plusReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "+", relayURL: nil)!
        let minusReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "-", relayURL: nil)!
        let heartReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "❤️", relayURL: nil)!
        let thumbsUpReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "👍", relayURL: nil)!
        let shakaReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "🤙", relayURL: nil)!

        XCTAssertEqual(to_reaction_emoji(ev: emptyReaction), "❤️")
        XCTAssertEqual(to_reaction_emoji(ev: plusReaction), "❤️")
        XCTAssertEqual(to_reaction_emoji(ev: minusReaction), "👎")
        XCTAssertEqual(to_reaction_emoji(ev: heartReaction), "❤️")
        XCTAssertEqual(to_reaction_emoji(ev: thumbsUpReaction), "👍")
        XCTAssertEqual(to_reaction_emoji(ev: shakaReaction), "🤙")
    }

    // MARK: - Custom Emoji Reaction Tests (NIP-25/NIP-30)

    func testCustomEmojiReactionContent() {
        let liked = NostrEvent(content: "test post", keypair: test_keypair, tags: [])!
        let customEmoji = CustomEmoji(shortcode: "soapbox", url: URL(string: "https://example.com/soapbox.png")!)

        let reaction = make_like_event(keypair: test_keypair_full, liked: liked, customEmoji: customEmoji, relayURL: nil)!

        XCTAssertEqual(reaction.content, ":soapbox:")
    }

    func testCustomEmojiReactionHasEmojiTag() {
        let liked = NostrEvent(content: "test post", keypair: test_keypair, tags: [])!
        let customEmoji = CustomEmoji(shortcode: "pepe", url: URL(string: "https://example.com/pepe.gif")!)

        let reaction = make_like_event(keypair: test_keypair_full, liked: liked, customEmoji: customEmoji, relayURL: nil)!

        let emojiTags = reaction.tags.filter { $0.count >= 3 && $0[0].matches_str("emoji") }
        XCTAssertEqual(emojiTags.count, 1)

        let emojiTag = emojiTags.first!
        XCTAssertEqual(emojiTag[1].string(), "pepe")
        XCTAssertEqual(emojiTag[2].string(), "https://example.com/pepe.gif")
    }

    func testCustomEmojiReactionPreservesEventTags() {
        let liked = NostrEvent(content: "test post", keypair: test_keypair, tags: [["p", "somepubkey"]])!
        let customEmoji = CustomEmoji(shortcode: "test", url: URL(string: "https://example.com/test.png")!)

        let reaction = make_like_event(keypair: test_keypair_full, liked: liked, customEmoji: customEmoji, relayURL: nil)!

        // Should have e tag, p tag(s), and emoji tag
        let eTags = reaction.tags.filter { $0[0].matches_char("e") }
        let pTags = reaction.tags.filter { $0[0].matches_char("p") }
        let emojiTags = reaction.tags.filter { $0[0].matches_str("emoji") }

        XCTAssertGreaterThan(eTags.count, 0, "Should have e tag")
        XCTAssertGreaterThan(pTags.count, 0, "Should have p tag")
        XCTAssertEqual(emojiTags.count, 1, "Should have exactly one emoji tag")
    }

    func testRegularReactionWithoutCustomEmoji() {
        let liked = NostrEvent(content: "test post", keypair: test_keypair, tags: [])!

        let reaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "🔥", relayURL: nil)!

        XCTAssertEqual(reaction.content, "🔥")

        let emojiTags = reaction.tags.filter { $0[0].matches_str("emoji") }
        XCTAssertEqual(emojiTags.count, 0, "Regular emoji reactions should not have emoji tags")
    }

}
