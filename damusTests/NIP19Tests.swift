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

    func test_parse_nprofile() throws {
        let res = parse_mentions(content: "nostr:nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p", tags: [])
        XCTAssertEqual(res.count, 1)
        let expected_ref = ReferencedId(ref_id: "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", relay_id: "wss://r.x.com", key: "p")
        let expected_mention = Mention(index: nil, type: .pubkey, ref: expected_ref)
        XCTAssertEqual(res[0], .mention(expected_mention))
    }
    
    func test_parse_npub() throws {
        let res = parse_mentions(content: "nostr:npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg ", tags: [])
        XCTAssertEqual(res.count, 2)
        let expected_ref = ReferencedId(ref_id: "7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e", relay_id: nil, key: "p")
        let expected_mention = Mention(index: nil, type: .pubkey, ref: expected_ref)
        XCTAssertEqual(res[0], .mention(expected_mention))
    }
    
    func test_parse_note() throws {
        let res = parse_mentions(content: " nostr:note1s4p70596lv50x0zftuses32t6ck8x6wgd4edwacyetfxwns2jtysux7vep", tags: [])
        XCTAssertEqual(res.count, 2)
        let expected_ref = ReferencedId(ref_id: "8543e7d0bafb28f33c495f2198454bd62c7369c86d72d77704cad2674e0a92c9", relay_id: nil, key: "e")
        let expected_mention = Mention(index: nil, type: .event, ref: expected_ref)
        XCTAssertEqual(res[1], .mention(expected_mention))
    }
    
    func test_mention_with_adjacent() throws {
        let res = parse_mentions(content: " nostr:note1s4p70596lv50x0zftuses32t6ck8x6wgd4edwacyetfxwns2jtysux7vep?", tags: [])
        XCTAssertEqual(res.count, 3)
        let expected_ref = ReferencedId(ref_id: "8543e7d0bafb28f33c495f2198454bd62c7369c86d72d77704cad2674e0a92c9", relay_id: nil, key: "e")
        let expected_mention = Mention(index: nil, type: .event, ref: expected_ref)
        XCTAssertEqual(res[0], .text(" "))
        XCTAssertEqual(res[1], .mention(expected_mention))
        XCTAssertEqual(res[2], .text("?"))
    }
    
    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
