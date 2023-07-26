//
//  HashtagTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-07-11.
//

import XCTest
@testable import damus

final class HashtagTests: XCTestCase {
    func testParseHashtag() {
        let parsed = parse_note_content(content: .content("some hashtag #bitcoin derp",nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "some hashtag ")
        XCTAssertEqual(parsed[1].is_hashtag, "bitcoin")
        XCTAssertEqual(parsed[2].is_text, " derp")
    }
    
    func testHashtagWithComma() {
        let parsed = parse_note_content(content: .content("some hashtag #bitcoin, cool",nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "some hashtag ")
        XCTAssertEqual(parsed[1].is_hashtag, "bitcoin")
        XCTAssertEqual(parsed[2].is_text, ", cool")
    }
    
    func testHashtagWithEmoji() {
        let content = "some hashtag #bitcoin☕️ cool"
        let parsed = parse_note_content(content: .content(content, nil)).blocks
        let post_blocks = parse_post_blocks(content: content)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "some hashtag ")
        XCTAssertEqual(parsed[1].is_hashtag, "bitcoin☕️")
        XCTAssertEqual(parsed[2].is_text, " cool")

        XCTAssertEqual(post_blocks.count, 3)
        XCTAssertEqual(post_blocks[0].is_text, "some hashtag ")
        XCTAssertEqual(post_blocks[1].is_hashtag, "bitcoin☕️")
        XCTAssertEqual(post_blocks[2].is_text, " cool")
    }

    func testPowHashtag() {
        let content = "pow! #ぽわ〜"
        let parsed = parse_note_content(content: .content(content,nil)).blocks
        let post_blocks = parse_post_blocks(content: content)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].is_text, "pow! ")
        XCTAssertEqual(parsed[1].is_hashtag, "ぽわ〜")

        XCTAssertEqual(post_blocks.count, 2)
        XCTAssertEqual(post_blocks[0].is_text, "pow! ")
        XCTAssertEqual(post_blocks[1].is_hashtag, "ぽわ〜")
    }

    func testHashtagWithAccents() {
        let parsed = parse_note_content(content: .content("hello from #türkiye",nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].is_text, "hello from ")
        XCTAssertEqual(parsed[1].is_hashtag, "türkiye")
    }

    func testHashtagWithNonLatinCharacters() {
        let parsed = parse_note_content(content: .content("this is a #시험 hope it works",nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "this is a ")
        XCTAssertEqual(parsed[1].is_hashtag, "시험")
        XCTAssertEqual(parsed[2].is_text, " hope it works")
    }
    
    func testParseHashtagEnd() {
        let parsed = parse_note_content(content: .content("some hashtag #bitcoin",nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].is_text, "some hashtag ")
        XCTAssertEqual(parsed[1].is_hashtag, "bitcoin")
    }
    
}
