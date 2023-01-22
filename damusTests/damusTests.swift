//
//  damusTests.swift
//  damusTests
//
//  Created by William Casarin on 2022-04-01.
//

import XCTest
@testable import damus

class damusTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    func testRandomBytes() {
        let bytes = random_bytes(count: 32)
        
        print("testRandomBytes \(hex_encode(bytes))")
        XCTAssertEqual(bytes.count, 32)
    }
    
    func testParseMentionWithMarkdown() {
        let md = """
        Testing markdown in damus
        
        **bold**

        _italics_

        `monospace`

        # h1

        ## h2

        ### h3

        * list1
        * list2

        > some awesome quote

        [my website](https://jb55.com)
        """
        
        let parsed = parse_mentions(content: md, tags: [])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertNotNil(parsed[0].is_text)
    }
    
    func testParseUrlUpper() {
        let parsed = parse_mentions(content: "a HTTPS://jb55.COM b", tags: [])

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[1].is_url?.absoluteString, "HTTPS://jb55.COM")
    }
    
    func testParseUrl() {
        let parsed = parse_mentions(content: "a https://jb55.com b", tags: [])

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[1].is_url?.absoluteString, "https://jb55.com")
    }
    
    func testParseUrlEnd() {
        let parsed = parse_mentions(content: "a https://jb55.com", tags: [])

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].is_text, "a ")
        XCTAssertEqual(parsed[1].is_url?.absoluteString, "https://jb55.com")
    }
    
    func testParseUrlStart() {
        let parsed = parse_mentions(content: "https://jb55.com br", tags: [])

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].is_url?.absoluteString, "https://jb55.com")
        XCTAssertEqual(parsed[1].is_text, " br")
    }
    
    func testNoParseUrlWithOnlyWhitespace() {
        let testString = "https:// "
        let parsed = parse_mentions(content: testString, tags: [])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[0].is_text, testString)
    }
    
    func testParseMentionBlank() {
        let parsed = parse_mentions(content: "", tags: [["e", "event_id"]])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 0)
    }
    
    func testMakeHashtagPost() {
        let privkey = "d05f5fcceef3e4529703f62a29222d6ee2d1b7bf1f24729b5e01df7c633cec8a"
        let pubkey = "6e59d3b78b1c1490a6489c94405873b57d8ef398a830ae5e39608f4107e9a790"
        let post = NostrPost(content: "#damus some content #bitcoin derp", references: [])
        let ev = post_to_event(post: post, privkey: privkey, pubkey: pubkey)
        
        XCTAssertEqual(ev.tags.count, 2)
        XCTAssertEqual(ev.content, "#damus some content #bitcoin derp")
        XCTAssertEqual(ev.tags[0][0], "t")
        XCTAssertEqual(ev.tags[0][1], "damus")
        XCTAssertEqual(ev.tags[1][0], "t")
        XCTAssertEqual(ev.tags[1][1], "bitcoin")
        
    }
    
    func testParseHashtag() {
        let parsed = parse_mentions(content: "some hashtag #bitcoin derp", tags: [])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "some hashtag ")
        XCTAssertEqual(parsed[1].is_hashtag, "bitcoin")
        XCTAssertEqual(parsed[2].is_text, " derp")
    }
    
    func testHashtagWithComma() {
        let parsed = parse_mentions(content: "some hashtag #bitcoin, cool", tags: [])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "some hashtag ")
        XCTAssertEqual(parsed[1].is_hashtag, "bitcoin")
        XCTAssertEqual(parsed[2].is_text, ", cool")
    }
    
    func testHashtagWithEmoji() {
        let parsed = parse_mentions(content: "some hashtag #bitcoin☕️ cool", tags: [])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].is_text, "some hashtag ")
        XCTAssertEqual(parsed[1].is_hashtag, "bitcoin")
        XCTAssertEqual(parsed[2].is_text, "☕️ cool")
    }
    
    func testParseHashtagEnd() {
        let parsed = parse_mentions(content: "some hashtag #bitcoin", tags: [])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].is_text, "some hashtag ")
        XCTAssertEqual(parsed[1].is_hashtag, "bitcoin")
    }
    
    func testParseMentionOnlyText() {
        let parsed = parse_mentions(content: "there is no mention here", tags: [["e", "event_id"]])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].is_text, "there is no mention here")
        
        guard case .text(let txt) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        
        XCTAssertEqual(txt, "there is no mention here")
    }

}
