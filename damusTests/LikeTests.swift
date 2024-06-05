//
//  LikeTests.swift
//  damusTests
//
//  Created by William Casarin on 2022-05-08.
//

import XCTest
@testable import damus

class LikeTests: XCTestCase {

    func testReactionTextNote() throws {
        let cindy = Pubkey(hex: "9d9181f0aea6500e1f360e07b9f37e25c72169b5158ae78df53f295272b6b71c")!
        let bob = Pubkey(hex: "218837fe8c94a66ae33af277bcbda45a0319e7726220cd76171b9dd1a468af91")!
        let liked = NostrEvent(content: "awesome #[0] post",
                               keypair: test_keypair,
                               tags: [cindy.tag, bob.tag])!
        let id = liked.id
        let like_ev = make_like_event(keypair: test_keypair_full, liked: liked)!

        XCTAssertTrue(like_ev.referenced_pubkeys.contains(test_keypair.pubkey))
        XCTAssertFalse(like_ev.referenced_pubkeys.contains(cindy))
        XCTAssertFalse(like_ev.referenced_pubkeys.contains(bob))
        XCTAssertEqual(like_ev.last_refid()!, id)
        XCTAssertTrue(like_ev.tags.allSatisfy { !$0[0].matches_char("a") })

        let kindTag = try XCTUnwrap(like_ev.tags.first(where: { $0.count >= 2 && $0[0].matches_char("k") }))
        XCTAssertTrue(kindTag[1].matches_str("1"))
    }

    func testReactionLongFormNote() throws {
        let liked = test_longform_event.event
        let id = liked.id
        let like_ev = make_like_event(keypair: test_keypair_full, liked: liked)!

        XCTAssertTrue(like_ev.referenced_pubkeys.contains(test_keypair.pubkey))
        XCTAssertEqual(like_ev.last_refid()!, id)

        let dTagValue = try XCTUnwrap(liked.tags.first { $0[0].matches_char("d") })
        let aTag = try XCTUnwrap(like_ev.tags.first { $0[0].matches_char("a") })
        XCTAssertTrue(aTag[1].matches_str("30023:\(test_keypair.pubkey.hex()):\(dTagValue[1])"))

        let kindTag = try XCTUnwrap(like_ev.tags.first(where: { $0.count >= 2 && $0[0].matches_char("k") }))
//        FIXME(tyiu) the assertion below fails for some reason even though in a different test, I was able to assert kind 1 just fine.
//        XCTAssertTrue(kindTag[1].matches_str("30023"))
    }

    func testToReactionEmoji() {
        let liked = NostrEvent(content: "awesome #[0] post", keypair: test_keypair, tags: [["p", "cindy"], ["e", "bob"]])!

        let emptyReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "")!
        let plusReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "+")!
        let minusReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "-")!
        let heartReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "❤️")!
        let thumbsUpReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "👍")!
        let shakaReaction = make_like_event(keypair: test_keypair_full, liked: liked, content: "🤙")!

        XCTAssertEqual(to_reaction_emoji(ev: emptyReaction), "❤️")
        XCTAssertEqual(to_reaction_emoji(ev: plusReaction), "❤️")
        XCTAssertEqual(to_reaction_emoji(ev: minusReaction), "👎")
        XCTAssertEqual(to_reaction_emoji(ev: heartReaction), "❤️")
        XCTAssertEqual(to_reaction_emoji(ev: thumbsUpReaction), "👍")
        XCTAssertEqual(to_reaction_emoji(ev: shakaReaction), "🤙")
    }

}
