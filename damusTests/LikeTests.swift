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
        let liked = NostrEvent(content: "awesome #[0] post", pubkey: "orig_pk", tags: [["p", "cindy"], ["e", "bob"]])
        liked.calculate_id()
        let id = liked.id
        let like_ev = make_like_event(pubkey: "pubkey", liked: liked)!
        
        XCTAssertTrue(like_ev.references(id: "orig_pk", key: "p"))
        XCTAssertTrue(like_ev.references(id: "cindy", key: "p"))
        XCTAssertTrue(like_ev.references(id: "bob", key: "e"))
        XCTAssertEqual(like_ev.last_refid()!.ref_id, id)
    }

}
