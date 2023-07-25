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
        let liked = NostrEvent(content: "awesome #[0] post", keypair: test_keypair, tags: [["p", "cindy"], ["e", "bob"]])!
        let id = liked.id
        let like_ev = make_like_event(keypair: test_keypair_full, liked: liked)!

        XCTAssertTrue(like_ev.references(id: test_keypair.pubkey, key: "p"))
        XCTAssertTrue(like_ev.references(id: "cindy", key: "p"))
        XCTAssertTrue(like_ev.references(id: "bob", key: "e"))
        XCTAssertEqual(like_ev.last_refid()!.ref_id, id)
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
