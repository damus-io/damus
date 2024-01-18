//
//  NoteContentViewTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-08-02.
//

import XCTest
import SwiftUI
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
    
    func testMentionStr_Pubkey_ContainsAbbreviated() throws {
        let compatibleText = createCompatibleText(test_pubkey.npub)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "17ldvg64:nq5mhr77")
    }
    
    func testMentionStr_Pubkey_ContainsFullBech32() {
        let compatableText = createCompatibleText(test_pubkey.npub)

        assertCompatibleTextHasExpectedString(compatibleText: compatableText, expected: test_pubkey.npub)
    }
    
    func testMentionStr_Nprofile_ContainsAbbreviated() throws {
        let compatibleText = createCompatibleText("nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p")
                
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "180cvv07:wsyjh6w6")
    }
    
    func testMentionStr_Nprofile_ContainsFullBech32() throws {
        let bech = "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: bech)
    }
    
    func testMentionStr_Note_ContainsAbbreviated() {
        let compatibleText = createCompatibleText(test_note.id.bech32)

        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "note1qqq:qqn2l0z3")
    }
    
    func testMentionStr_Note_ContainsFullBech32() {
        let compatableText = createCompatibleText(test_note.id.bech32)

        assertCompatibleTextHasExpectedString(compatibleText: compatableText, expected: test_note.id.bech32)
    }
    
    func testMentionStr_Nevent_ContainsAbbreviated() {
        let bech = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm"
        let compatibleText = createCompatibleText(bech)

        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "nevent1q:t5nxnepm")
    }
    
    func testMentionStr_Nevent_ContainsFullBech32() throws {
        let bech = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: bech)
    }
    
    func testMentionStr_Nrelay_ContainsAbbreviated() {
        let bech = "nrelay1qqt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueq4r295t"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "wss://relay.nostr.band")
    }
    
    func testMentionStr_Nrelay_ContainsFullBech32() {
        let bech = "nrelay1qqt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueq4r295t"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: bech)
    }
    
    func testMentionStr_Naddr_ContainsAbbreviated() {
        let bech = "naddr1qqxnzdesxqmnxvpexqunzvpcqyt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueqzypve7elhmamff3sr5mgxxms4a0rppkmhmn7504h96pfcdkpplvl2jqcyqqq823cnmhuld"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "naddr1qq:3cnmhuld")
    }
    
    func testMentionStr_Naddr_ContainsFullBech32() {
        let bech = "naddr1qqxnzdesxqmnxvpexqunzvpcqyt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueqzypve7elhmamff3sr5mgxxms4a0rppkmhmn7504h96pfcdkpplvl2jqcyqqq823cnmhuld"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: bech)
    }

}

private func assertCompatibleTextHasExpectedString(compatibleText: CompatibleText, expected: String) {
    guard let hasExpected = compatibleText.items.first?.attributed_string()?.description.contains(expected) else {
        XCTFail()
        return
    }
    
    XCTAssertTrue(hasExpected)
}

private func createCompatibleText(_ bechString: String) -> CompatibleText {
    guard let mentionRef = Bech32Object.parse(bechString)?.toMentionRef() else {
        XCTFail("Failed to create MentionRef from Bech32 string")
        return CompatibleText()
    }
    return mention_str(.any(mentionRef), profiles: test_damus_state.profiles)
}
