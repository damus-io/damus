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
    
    func testParseMention() throws {
        let parsed = parse_mentions(content: "this is #[0] a mention", tags: [["e", "event_id"]])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_mention)
        XCTAssertTrue(parsed[2].is_text)
    }
    
    func testEmptyPostReference() throws {
        let parsed = parse_post_blocks(content: "")
        XCTAssertEqual(parsed.count, 0)
    }
    
    func testInvalidPostReference() throws {
        let pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e24"
        let content = "this is a @\(pk) mention"
        let parsed = parse_post_blocks(content: content)
        XCTAssertEqual(parsed.count, 1)
        guard case .text(let txt) = parsed[0] else {
            XCTAssert(false)
            return
        }
        XCTAssertEqual(txt, content)
    }
    
    func testInvalidPostReferenceEmptyAt() throws {
        let content = "this is a @ mention"
        let parsed = parse_post_blocks(content: content)
        XCTAssertEqual(parsed.count, 1)
        guard case .text(let txt) = parsed[0] else {
            XCTAssert(false)
            return
        }
        XCTAssertEqual(txt, content)
    }
    
    func testFunnyUriReference() throws {
        let id = "6fec2ee6cfff779fe8560976b3d9df782b74577f0caefa7a77c0ed4c3749b5de"
        let content = "this is a nostr:&\(id):\(id) event mention"
        let parsed = parse_post_blocks(content: content)
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_ref)
        XCTAssertTrue(parsed[2].is_text)
        
        guard case .ref(let ref) = parsed[1] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(ref.ref_id, id)
        XCTAssertEqual(ref.key, "e")
        XCTAssertNil(ref.relay_id)
        
        guard case .text(let t1) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t1, "this is a nostr:")
        
        guard case .text(let t2) = parsed[2] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t2, ":\(id) event mention")
    }
    
    func testInvalidUriReference() throws {
        let id = "6fec2ee6cfff779fe8560976b3d9df782b74577f0caefa7a77c0ed4c3749b5de"
        let content = "this is a nostr:z:\(id) event mention"
        let parsed = parse_post_blocks(content: content)
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 1)
        
        guard case .text(let txt) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        
        XCTAssertEqual(txt, content)
    }
    
    func testParsePostUriPubkeyReference() throws {
        let id = "6fec2ee6cfff779fe8560976b3d9df782b74577f0caefa7a77c0ed4c3749b5de"
        let parsed = parse_post_blocks(content: "this is a nostr:p:\(id) event mention")
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_ref)
        XCTAssertTrue(parsed[2].is_text)
        
        guard case .ref(let ref) = parsed[1] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(ref.ref_id, id)
        XCTAssertEqual(ref.key, "p")
        XCTAssertNil(ref.relay_id)
        
        guard case .text(let t1) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t1, "this is a ")
        
        guard case .text(let t2) = parsed[2] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t2, " event mention")
    }
    
    func testParsePostUriReference() throws {
        let id = "6fec2ee6cfff779fe8560976b3d9df782b74577f0caefa7a77c0ed4c3749b5de"
        let parsed = parse_post_blocks(content: "this is a nostr:e:\(id) event mention")
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_ref)
        XCTAssertTrue(parsed[2].is_text)
        
        guard case .ref(let ref) = parsed[1] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(ref.ref_id, id)
        XCTAssertEqual(ref.key, "e")
        XCTAssertNil(ref.relay_id)
        
        guard case .text(let t1) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t1, "this is a ")
        
        guard case .text(let t2) = parsed[2] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t2, " event mention")
    }
    
    func testParsePostEventReference() throws {
        let pk = "6fec2ee6cfff779fe8560976b3d9df782b74577f0caefa7a77c0ed4c3749b5de"
        let parsed = parse_post_blocks(content: "this is a &\(pk) event mention")
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_ref)
        XCTAssertTrue(parsed[2].is_text)
        
        guard case .ref(let ref) = parsed[1] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(ref.ref_id, pk)
        XCTAssertEqual(ref.key, "e")
        XCTAssertNil(ref.relay_id)
        
        guard case .text(let t1) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t1, "this is a ")
        
        guard case .text(let t2) = parsed[2] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t2, " event mention")
    }
    
    func testParsePostPubkeyReference() throws {
        let pk = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let parsed = parse_post_blocks(content: "this is a @\(pk) mention")
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertTrue(parsed[0].is_text)
        XCTAssertTrue(parsed[1].is_ref)
        XCTAssertTrue(parsed[2].is_text)
        
        guard case .ref(let ref) = parsed[1] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(ref.ref_id, pk)
        XCTAssertEqual(ref.key, "p")
        XCTAssertNil(ref.relay_id)
        
        guard case .text(let t1) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t1, "this is a ")
        
        guard case .text(let t2) = parsed[2] else {
            XCTAssertTrue(false)
            return
        }
        XCTAssertEqual(t2, " mention")
    }
    
    func testParseInvalidMention() throws {
        let parsed = parse_mentions(content: "this is #[0] a mention", tags: [])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertTrue(parsed[0].is_text)
        
        guard case .text(let txt) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        
        XCTAssertEqual(txt, "this is #[0] a mention")
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
        XCTAssertTrue(parsed[0].is_text)
    }
    
    func testParseMentionBlank() {
        let parsed = parse_mentions(content: "", tags: [["e", "event_id"]])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 0)
    }
    
    func testParseMentionOnlyText() {
        let parsed = parse_mentions(content: "there is no mention here", tags: [["e", "event_id"]])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertTrue(parsed[0].is_text)
        
        guard case .text(let txt) = parsed[0] else {
            XCTAssertTrue(false)
            return
        }
        
        XCTAssertEqual(txt, "there is no mention here")
    }

}
