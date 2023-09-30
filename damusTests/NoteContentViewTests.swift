//
//  NoteContentViewTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-08-02.
//

import XCTest
@testable import damus

class NoteContentViewTests: XCTestCase {
    func testRenderBlocksWithNonLatinHashtags() {
        let content = "Damusはかっこいいです #cool #かっこいい"
        let note = NostrEvent(content: content, keypair: test_keypair, tags: [["t", "かっこいい"]])!
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state
        
        let text: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles)
        let attributedText: AttributedString = text.content.attributed
        
        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        print(runArray.description)
        XCTAssertEqual(runArray[1].link?.absoluteString, "damus:t:cool", "Latin-character hashtag is missing. Runs description :\(runArray.description)")
        XCTAssertEqual(runArray[3].link?.absoluteString.removingPercentEncoding!, "damus:t:かっこいい", "Non-latin-character hashtag is missing. Runs description :\(runArray.description)")
    }
    
    /// Based on https://github.com/damus-io/damus/issues/1468
    /// Tests whether a note content view correctly parses an image block when url in JSON content contains optional escaped slashes
    func testParseImageBlockInContentWithEscapedSlashes() {
        let testJSONWithEscapedSlashes = "{\"tags\":[],\"pubkey\":\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\",\"content\":\"https:\\/\\/cdn.nostr.build\\/i\\/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg\",\"created_at\":1691864981,\"kind\":1,\"sig\":\"fc0033aa3d4df50b692a5b346fa816fdded698de2045e36e0642a021391468c44ca69c2471adc7e92088131872d4aaa1e90ea6e1ad97f3cc748f4aed96dfae18\",\"id\":\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\"}"
        let testNote = NostrEvent.owned_from_json(json: testJSONWithEscapedSlashes)!
        let parsed = parse_note_content(content: .init(note: testNote, keypair: test_keypair))
        
        XCTAssertTrue((parsed.blocks[0].asURL != nil), "NoteContentView does not correctly parse an image block when url in JSON content contains optional escaped slashes.")
    }

}
