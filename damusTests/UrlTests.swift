//
//  UrlTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-08-06.
//

import XCTest
@testable import damus

final class UrlTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testRelayUrlStripsEndingSlash() throws {
        let url1 = RelayURL("wss://jb55.com/")!
        let url2 = RelayURL("wss://jb55.com")!
        XCTAssertEqual(url1, url2)
        XCTAssertEqual(url1.url.absoluteString, "wss://jb55.com")
    }

    func testParseUrlTrailingParenthesis() {
        let testString = "https://en.m.wikipedia.org/wiki/Delicious_(website)"
        let parsed = parse_note_content(content: .content(testString, nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[0].is_url?.absoluteString, testString)
    }

    func testParseUrlTrailingParenthesisAndInitialParenthesis() {
        let testString = "( https://en.m.wikipedia.org/wiki/Delicious_(website)"
        let parsed = parse_note_content(content: .content(testString, nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[1].is_url?.absoluteString, "https://en.m.wikipedia.org/wiki/Delicious_(website)")
    }

    func testParseUrlTrailingParenthesisShouldntParse() {
        let testString = "(https://jb55.com)"
        let parsed = parse_note_content(content: .content(testString, nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[1].is_url?.absoluteString, "https://jb55.com")
    }

    func testLinkIsNotAHashtag() {
        let link = "https://github.com/damus-io/damus/blob/b7513f28fa1d31c2747865067256ad1d7cf43aac/damus/Nostr/NostrEvent.swift#L560"

        let content = "my \(link) link"
        let blocks = parse_post_blocks(content: content)

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].is_text, "my ")
        XCTAssertEqual(blocks[1].is_url, URL(string: link)!)
        XCTAssertEqual(blocks[2].is_text, " link")
    }

    func testParseUrlUpper() {
        let parsed = parse_note_content(content: .content("a HTTPS://jb55.COM b", nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[1].is_url?.absoluteString, "HTTPS://jb55.COM")
    }
    
    func testUrlAnchorsAreNotHashtags() {
        let content = "this is my link: https://jb55.com/index.html#buybitcoin this is not a hashtag!"
        let blocks = parse_post_blocks(content: content)

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].is_text, "this is my link: ")
        XCTAssertEqual(blocks[1].is_url, URL(string: "https://jb55.com/index.html#buybitcoin")!)
        XCTAssertEqual(blocks[2].is_text, " this is not a hashtag!")
    }

}
