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

    func testPurpleUrls() {
        let landing_staging = DamusPurpleURL(is_staging: true, variant: .landing)
        let welcome_staging = DamusPurpleURL(is_staging: true, variant: .welcome(checkout_id: "abc"))
        let verify_staging  = DamusPurpleURL(is_staging: true, variant: .verify_npub(checkout_id: "abc"))

        let landing = DamusPurpleURL(is_staging: false, variant: .landing)
        let welcome = DamusPurpleURL(is_staging: false, variant: .welcome(checkout_id: "abc"))
        let verify  = DamusPurpleURL(is_staging: false, variant: .verify_npub(checkout_id: "abc"))

        XCTAssertEqual(landing_staging, .init(url: URL(string: landing_staging.url_string())!)!)
        XCTAssertEqual(welcome_staging, .init(url: URL(string: welcome_staging.url_string())!)!)
        XCTAssertEqual(verify_staging, .init(url: URL(string: verify_staging.url_string())!)!)

        XCTAssertEqual(landing, .init(url: URL(string: landing.url_string())!)!)
        XCTAssertEqual(welcome, .init(url: URL(string: welcome.url_string())!)!)
        XCTAssertEqual(verify, .init(url: URL(string: verify.url_string())!)!)
    }

    func testParseUrlTrailingParenthesis() {
        let testURL = URL(string: "https://en.m.wikipedia.org/wiki/Delicious_(website)")
        XCTAssertNotNil(testURL)
        
        let testString = "https://en.m.wikipedia.org/wiki/Delicious_(website)"
        
        let parsed = parse_note_content(content: .content(testString, nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[0].asURL, testURL)
    }

    func testParseUrlTrailingParenthesisAndInitialParenthesis() {
        let testURL = URL(string: "https://en.m.wikipedia.org/wiki/Delicious_(website)")
        XCTAssertNotNil(testURL)
        
        let testString = "( https://en.m.wikipedia.org/wiki/Delicious_(website)"
        let parsed = parse_note_content(content: .content(testString, nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[1].asURL, testURL)
    }

    func testParseUrlTrailingParenthesisShouldntParse() {
        let testURL = URL(string: "https://jb55.com")
        XCTAssertNotNil(testURL)
        
        let testString = "(https://jb55.com)"
        let parsed = parse_note_content(content: .content(testString, nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[1].asURL, testURL)
    }

    func testParseSmartParens() {
        let testURL = URL(string: "https://nostr-con.com/simplex")
        XCTAssertNotNil(testURL)
        
        let testString = "(https://nostr-con.com/simplex)"
        let parsed = parse_note_content(content: .content(testString, nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[1].asURL, testURL)
    }

    func testLinkIsNotAHashtag() {
        let link = "https://github.com/damus-io/damus/blob/b7513f28fa1d31c2747865067256ad1d7cf43aac/damus/Nostr/NostrEvent.swift#L560"
        let testURL = URL(string: link)
        XCTAssertNotNil(testURL)

        let content = "my \(link) link"
        let blocks = parse_post_blocks(content: content)!.blocks

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].asText, "my ")
        XCTAssertEqual(blocks[1].asURL, testURL)
        XCTAssertEqual(blocks[2].asText, " link")
    }

    func testParseUrlUpper() {
        let testURL = URL(string: "HTTPS://jb55.COM")
        XCTAssertNotNil(testURL)
        
        let parsed = parse_note_content(content: .content("a HTTPS://jb55.COM b", nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[1].asURL, testURL)
    }
    
    func testUrlAnchorsAreNotHashtags() {
        let testURL = URL(string: "https://jb55.com/index.html#buybitcoin")
        XCTAssertNotNil(testURL)
        
        let content = "this is my link: https://jb55.com/index.html#buybitcoin this is not a hashtag!"
        let blocks = parse_post_blocks(content: content)!.blocks

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].asText, "this is my link: ")
        XCTAssertEqual(blocks[1].asURL, testURL)
        XCTAssertEqual(blocks[2].asText, " this is not a hashtag!")
    }
    
    func testParseURL_OneURLEndPeriodSimple_RemovesPeriod(){
        testParseURL(inputURLString: "http://example.com.", expectedURLs: "http://example.com")
    }
    
    func testParseURL_OneURL_RemovesPeriod(){
        testParseURL(inputURLString: "http://example.com/.test", expectedURLs: "http://example.com/.test")
    }
    
    func testParseURL_OneURLEndPeriodAndSpaceSimple_RemovesPeriod(){
        testParseURL(inputURLString: "http://example.com. ", expectedURLs: "http://example.com")
    }
    
    func testParseURL_OneURLEndPeriodComplex_RemovesPeriod(){
        testParseURL(inputURLString: "http://example.com/test.", expectedURLs: "http://example.com/test")
    }
    
    func testParseURL_TwoURLEndPeriodSimple_RemovesPeriods(){
        testParseURL(inputURLString: "http://example.com. http://example.com.", expectedURLs: "http://example.com", "http://example.com")
    }
    
    func testParseURL_ThreeURLEndPeriodSimple_RemovesPeriods(){
        testParseURL(inputURLString: "http://example.com. http://example.com. http://example.com.", expectedURLs: "http://example.com", "http://example.com", "http://example.com")
    }
    
    func testParseURL_TwoURLEndPeriodFirstComplexSecondSimple_RemovesPeriods(){
        testParseURL(inputURLString: "http://example.com/test. http://example.com.", expectedURLs: "http://example.com/test", "http://example.com")
    }
    
    func testParseURL_TwoURLEndPeriodFirstSimpleSecondComplex_RemovesPeriods(){
        testParseURL(inputURLString: "http://example.com. http://example.com/test.", expectedURLs: "http://example.com", "http://example.com/test")
    }
    
    func testParseURL_TwoURLEndPeriodFirstComplexSecondComplex_RemovesPeriods(){
        testParseURL(inputURLString: "http://example.com/test. http://example.com/test.", expectedURLs: "http://example.com/test", "http://example.com/test")
    }
    
    func testParseURL_OneURLEndPeriodSerachQuery_RemovesPeriod(){
        testParseURL(inputURLString: "https://www.example.com/search?q=test+query.", expectedURLs: "https://www.example.com/search?q=test+query")
    }
    
    func testParseURL_OneURLEndComma_RemovesComma(){
        testParseURL(inputURLString: "http://example.com,", expectedURLs: "http://example.com")
    }
    
    func testParseURL_OneURL_RemovesComma(){
        testParseURL(inputURLString: "http://example.com/,test", expectedURLs: "http://example.com/,test")
    }
    
    func testParseURL_OneURLEndCommaAndSpaceSimple_RemovesComma(){
        testParseURL(inputURLString: "http://example.com, ", expectedURLs: "http://example.com")
    }
    
    func testParseURL_OneURLEndCommaComplex_RemovesComma(){
        testParseURL(inputURLString: "http://example.com/test,", expectedURLs: "http://example.com/test")
    }
    
    func testParseURL_TwoURLEndCommaSimple_RemovesCommas(){
        testParseURL(inputURLString: "http://example.com, http://example.com,", expectedURLs: "http://example.com", "http://example.com")
    }
    
    func testParseURL_ThreeURLEndCommaSimple_RemovesCommas(){
        testParseURL(inputURLString: "http://example.com, http://example.com, http://example.com,", expectedURLs: "http://example.com", "http://example.com", "http://example.com")
    }
    
    func testParseURL_TwoURLEndCommaFirstComplexSecondSimple_RemovesCommas(){
        testParseURL(inputURLString: "http://example.com/test, http://example.com,", expectedURLs: "http://example.com/test", "http://example.com")
    }
    
    func testParseURL_TwoURLEndCommaFirstSimpleSecondComplex_RemovesCommas(){
        testParseURL(inputURLString: "http://example.com, http://example.com/test,", expectedURLs: "http://example.com", "http://example.com/test")
    }
    
    func testParseURL_TwoURLEndCommaFirstComplexSecondComplex_RemovesCommas(){
        testParseURL(inputURLString: "http://example.com/test, http://example.com/test,", expectedURLs: "http://example.com/test", "http://example.com/test")
    }
    
    func testParseURL_OneURLEndCommaSerachQuery_RemovesComma(){
        testParseURL(inputURLString: "https://www.example.com/search?q=test+query,", expectedURLs: "https://www.example.com/search?q=test+query")
    }
    
    func testParseURL_TwoURLFirstSimpleSecondSimpleNoSpace_RemovesCommas(){
        testParseURL(inputURLString: "http://example.com,http://example.com,",
        expectedURLs: "http://example.com", "http://example.com")
    }
}

func testParseURL(inputURLString: String, expectedURLs: String...) {
    let parsedURL: [Block] = parse_note_content(content: .content(inputURLString, nil))!.blocks.filter {
        $0.isURL
    }
    
    if(expectedURLs.count != parsedURL.count) {
        XCTFail()
    }
    
    for i in 0..<parsedURL.count {
        guard let expectedURL = URL(string: expectedURLs[i]) else {
            XCTFail()
            return
        }

        XCTAssertEqual(parsedURL[i].asURL, expectedURL)
    }
}
