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

    func testIdEquality() throws {
        let pubkey = test_pubkey
        let ev = test_note

        let pubkey_same = Pubkey(Data([0xf7, 0xda, 0xc4, 0x6a, 0xa2, 0x70, 0xf7, 0x28, 0x76, 0x06, 0xa2, 0x2b, 0xeb, 0x4d, 0x77, 0x25, 0x57, 0x3a, 0xfa, 0x0e, 0x02, 0x8c, 0xdf, 0xac, 0x39, 0xa4, 0xcb, 0x23, 0x31, 0x53, 0x7f, 0x66]))

        XCTAssertEqual(pubkey.hashValue, pubkey_same.hashValue)
        XCTAssertEqual(pubkey, pubkey_same)
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
    
    func testTrimmingFunctions() {
        let txt = "   bobs   "
        
        XCTAssertEqual(trim_prefix(txt), "bobs   ")
        XCTAssertEqual(trim_suffix(txt), "   bobs")
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
        
        let parsed = parse_note_content(content: .content(md, nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertNotNil(parsed[0].is_text)
        XCTAssertNotNil(parsed[1].is_url)
        XCTAssertNotNil(parsed[2].is_text)
    }

    func testStringArrayStorage() {
        let key = "test_key_string_values"
        let scoped_key = setting_property_key(key: key)

        let res = setting_set_property_value(scoped_key: scoped_key, old_value: [], new_value: ["a"])
        XCTAssertEqual(res, ["a"])

        let got = setting_get_property_value(key: key, scoped_key: scoped_key, default_value: [String]())
        XCTAssertEqual(got, ["a"])

        _ = setting_set_property_value(scoped_key: scoped_key, old_value: got, new_value: ["a", "b", "c"])
        let got2 = setting_get_property_value(key: key, scoped_key: scoped_key, default_value: [String]())
        XCTAssertEqual(got2, ["a", "b", "c"])
    }

    func testBech32Url()  {
        let parsed = decode_nostr_uri("nostr:npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s")
        
        let pk = Pubkey(hex:"32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        XCTAssertEqual(parsed, .ref(.pubkey(pk)))
    }
    
    func testSaveRelayFilters() {
        var filters = Set<RelayFilter>()
        
        let filter1 = RelayFilter(timeline: .search, relay_id: "wss://abc.com")
        let filter2 = RelayFilter(timeline: .home, relay_id: "wss://abc.com")
        filters.insert(filter1)
        filters.insert(filter2)
        
        save_relay_filters(test_pubkey, filters: filters)
        let loaded_filters = load_relay_filters(test_pubkey)!

        XCTAssertEqual(loaded_filters.count, 2)
        XCTAssertTrue(loaded_filters.contains(filter1))
        XCTAssertTrue(loaded_filters.contains(filter2))
        XCTAssertEqual(filters, loaded_filters)
    }
    
    func testParseUrl() {
        let parsed = parse_note_content(content: .content("a https://jb55.com b", nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[1].is_url?.absoluteString, "https://jb55.com")
    }
    
    func testParseUrlEnd() {
        let parsed = parse_note_content(content: .content("a https://jb55.com", nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].is_text, "a ")
        XCTAssertEqual(parsed[1].is_url?.absoluteString, "https://jb55.com")
    }
    
    func testParseUrlStart() {
        let parsed = parse_note_content(content: .content("https://jb55.com br",nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].is_url?.absoluteString, "https://jb55.com")
        XCTAssertEqual(parsed[1].is_text, " br")
    }
    
    func testNoParseUrlWithOnlyWhitespace() {
        let testString = "https://  "
        let parsed = parse_note_content(content: .content(testString,nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[0].is_text, testString)
    }
    
    func testNoParseUrlTrailingCharacters() {
        let testString = "https://foo.bar, "
        let parsed = parse_note_content(content: .content(testString,nil)).blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed[0].is_url?.absoluteString, "https://foo.bar")
    }


    /*
    func testParseMentionBlank() {
        let parsed = parse_note_content(content: "", tags: [["e", "event_id"]]).blocks
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 0)
    }
     */

    func testMakeHashtagPost() {
        let post = NostrPost(content: "#damus some content #bitcoin derp #かっこいい wow", references: [])
        let ev = post_to_event(post: post, keypair: test_keypair_full)!

        XCTAssertEqual(ev.tags.count, 3)
        XCTAssertEqual(ev.content, "#damus some content #bitcoin derp #かっこいい wow")
        XCTAssertEqual(ev.tags[0][0].string(), "t")
        XCTAssertEqual(ev.tags[0][1].string(), "damus")
        XCTAssertEqual(ev.tags[1][0].string(), "t")
        XCTAssertEqual(ev.tags[1][1].string(), "bitcoin")
        XCTAssertEqual(ev.tags[2][0].string(), "t")
        XCTAssertEqual(ev.tags[2][1].string(), "かっこいい")
    }

    func testParseMentionOnlyText() {
        let tags = [["e", "event_id"]]
        let ev = NostrEvent(content: "there is no mention here", keypair: test_keypair, tags: tags)!
        let parsed = parse_note_content(content: .init(note: ev, keypair: test_keypair)).blocks

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
