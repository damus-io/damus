//
//  LargeEventTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-08-05.
//

import XCTest
@testable import damus

final class LargeEventTests: XCTestCase {

    func testLongPost() async throws {
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
        let shouldShowEvent = await should_show_event(state: test_damus_state, ev: ev)
        XCTAssertTrue(shouldShowEvent)
        XCTAssertTrue(validate_event(ev: ev) == .ok)
    }

    func testIsHellthread() throws {
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
        XCTAssertTrue(ev.is_hellthread(max_pubkeys: 10))
        XCTAssertTrue(validate_event(ev: ev) == .ok)
    }

}
