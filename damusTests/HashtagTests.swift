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
        
        XCTAssertEqual(parsed[0].asText, "some hashtag ")
        XCTAssertEqual(parsed[1].asHashtag, "bitcoin")
        XCTAssertEqual(parsed[2].asText, " derp")
    }
    
    func testHashtagWithComma() {
        let parsed = parse_note_content(content: .content("some hashtag #bitcoin, cool",nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "some hashtag ")
        XCTAssertEqual(parsed[1].asHashtag, "bitcoin")
        XCTAssertEqual(parsed[2].asText, ", cool")
    }
    
    func testHashtagWithEmoji() {
        let content = "some hashtag #bitcoin☕️ cool"
        let parsed = parse_note_content(content: .content(content, nil)).blocks
        let post_blocks = parse_post_blocks(content: content)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "some hashtag ")
        XCTAssertEqual(parsed[1].asHashtag, "bitcoin☕️")
        XCTAssertEqual(parsed[2].asText, " cool")

        XCTAssertEqual(post_blocks.count, 3)
        XCTAssertEqual(post_blocks[0].asText, "some hashtag ")
        XCTAssertEqual(post_blocks[1].asHashtag, "bitcoin☕️")
        XCTAssertEqual(post_blocks[2].asText, " cool")
    }

    func testPowHashtag() {
        let content = "pow! #ぽわ〜"
        let parsed = parse_note_content(content: .content(content,nil)).blocks
        let post_blocks = parse_post_blocks(content: content)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].asText, "pow! ")
        XCTAssertEqual(parsed[1].asHashtag, "ぽわ〜")

        XCTAssertEqual(post_blocks.count, 2)
        XCTAssertEqual(post_blocks[0].asText, "pow! ")
        XCTAssertEqual(post_blocks[1].asHashtag, "ぽわ〜")
    }

    func testHashtagWithAccents() {
        let parsed = parse_note_content(content: .content("hello from #türkiye",nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].asText, "hello from ")
        XCTAssertEqual(parsed[1].asHashtag, "türkiye")
    }

    func testHashtagWithNonLatinCharacters() {
        let parsed = parse_note_content(content: .content("this is a #시험 hope it works",nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "this is a ")
        XCTAssertEqual(parsed[1].asHashtag, "시험")
        XCTAssertEqual(parsed[2].asText, " hope it works")
    }
    
    func testParseHashtagEnd() {
        let parsed = parse_note_content(content: .content("some hashtag #bitcoin",nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].asText, "some hashtag ")
        XCTAssertEqual(parsed[1].asHashtag, "bitcoin")
    }
    
}
