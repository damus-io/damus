//
//  LongPostTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-08-05.
//

import XCTest
@testable import damus

final class LongPostTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testLongPost() throws {
        let contacts = Contacts(our_pubkey: test_keypair.pubkey)
        let json = "[\"EVENT\",\"subid\",\(test_failing_nostr_report)]"
        let resp = NostrResponse.owned_from_json(json: json)

        XCTAssertNotNil(resp)
        guard let resp,
              case .event(let subid, let ev) = resp
        else {
            XCTAssertFalse(true)
            return
        }

        XCTAssertEqual(subid, "subid")
        XCTAssertTrue(ev.should_show_event)
        XCTAssertTrue(!ev.too_big)
        XCTAssertTrue(should_show_event(state: test_damus_state, ev: ev))
        XCTAssertTrue(validate_event(ev: ev) == .ok )
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
