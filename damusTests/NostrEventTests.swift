//
//  NostrEventTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-08-15.
//

import Foundation
import XCTest
@testable import damus

final class NostrEventTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    /// Based on https://github.com/damus-io/damus/issues/1468
    /// Tests whether `decode_nostr_event` correctly decodes nostr note image content written with optional escaped slashes
    func testDecodeNostrEventWithEscapedSlashes() throws {
        let testMessageString = "[\"EVENT\",\"A54091AC-D144-49F6-853A-2141A5EA09B6\",{\"content\":\"{\\\"tags\\\":[],\\\"pubkey\\\":\\\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\\\",\\\"content\\\":\\\"https:\\\\/\\\\/cdn.nostr.build\\\\/i\\\\/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg\\\",\\\"created_at\\\":1691864981,\\\"kind\\\":1,\\\"sig\\\":\\\"fc0033aa3d4df50b692a5b346fa816fdded698de2045e36e0642a021391468c44ca69c2471adc7e92088131872d4aaa1e90ea6e1ad97f3cc748f4aed96dfae18\\\",\\\"id\\\":\\\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\\\"}\",\"created_at\":1691866192,\"id\":\"56e3f14cedab76762afef78eeb34b07ce1313543a2f3365a7b99fd5daa65abc9\",\"kind\":6,\"pubkey\":\"32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245\",\"sig\":\"3c1161c3b03cafe13e2d9d624b158bdb74867caf61df158871633c859cd587e7779d096680de34024d9acfcba9aa3cb76fdbfa20227afb7e03a9ab588e6b77c9\",\"tags\":[[\"e\",\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\",\"\",\"root\"],[\"p\",\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\"]]}]"
        let response: NostrResponse = decode_nostr_event(txt: testMessageString)!
        guard case .event(_, let testEvent) = response else {
            XCTAssert(false, "Could not decode event")
            return
        }
        let urlInContent = "https:\\/\\/cdn.nostr.build\\/i\\/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg"
        XCTAssert(testEvent.content.contains(urlInContent), "Issue parsing event. Expected to see '\(urlInContent)' inside \(testEvent.content)")
        
        let testMessageString2 = "[\"EVENT\",\"A54091AC-D144-49F6-853A-2141A5EA09B6\",{\"content\":\"{\\\"tags\\\":[],\\\"pubkey\\\":\\\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\\\",\\\"content\\\":\\\"https:\\/\\/cdn.nostr.build\\/i\\/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg\\\",\\\"created_at\\\":1691864981,\\\"kind\\\":1,\\\"sig\\\":\\\"fc0033aa3d4df50b692a5b346fa816fdded698de2045e36e0642a021391468c44ca69c2471adc7e92088131872d4aaa1e90ea6e1ad97f3cc748f4aed96dfae18\\\",\\\"id\\\":\\\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\\\"}\",\"created_at\":1691866192,\"id\":\"56e3f14cedab76762afef78eeb34b07ce1313543a2f3365a7b99fd5daa65abc9\",\"kind\":6,\"pubkey\":\"32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245\",\"sig\":\"3c1161c3b03cafe13e2d9d624b158bdb74867caf61df158871633c859cd587e7779d096680de34024d9acfcba9aa3cb76fdbfa20227afb7e03a9ab588e6b77c9\",\"tags\":[[\"e\",\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\",\"\",\"root\"],[\"p\",\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\"]]}]"
        let response2: NostrResponse = decode_nostr_event(txt: testMessageString2)!
        guard case .event(_, let testEvent2) = response2 else {
            XCTAssert(false, "Could not decode event")
            return
        }
        let urlInContent2 = "https://cdn.nostr.build/i/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg"
        XCTAssert(testEvent2.content.contains(urlInContent2), "Issue parsing event. Expected to see '\(urlInContent2)' inside \(testEvent2.content)")
    }
    
    func testClientTagParsing() {
        let tags = [["client", "Custom Client", "addr", "wss://relay.example"], ["p", test_pubkey.hex()]]
        let event = NostrEvent(content: "hi", keypair: test_keypair, kind: 1, tags: tags)!
        let metadata = event.clientTag
        XCTAssertEqual(metadata?.name, "Custom Client")
        XCTAssertEqual(metadata?.handlerAddress, "addr")
        XCTAssertEqual(metadata?.relayHint, "wss://relay.example")
    }

    func testClientTagNilWhenMissing() {
        let event = NostrEvent(content: "hi", keypair: test_keypair, kind: 1, tags: [])!
        XCTAssertNil(event.clientTag)
    }
}
