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
        let privkey = "0fc2092231f958f8d57d66f5e238bb45b6a2571f44c0ce024bbc6f3a9c8a15fe"
        let pubkey  = "30c6d1dc7f7c156794fa15055e651b758a61b99f50fcf759de59386050bf6ae2"
        let liked = NostrEvent(content: "awesome #[0] post", pubkey: "orig_pk", tags: [["p", "cindy"], ["e", "bob"]])
        liked.calculate_id()
        let id = liked.id
        let like_ev = make_like_event(pubkey: pubkey, privkey: privkey, liked: liked)
        
        XCTAssertTrue(like_ev.references(id: "orig_pk", key: "p"))
        XCTAssertTrue(like_ev.references(id: "cindy", key: "p"))
        XCTAssertTrue(like_ev.references(id: "bob", key: "e"))
        XCTAssertEqual(like_ev.last_refid()!.ref_id, id)
    }

}
