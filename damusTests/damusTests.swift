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
