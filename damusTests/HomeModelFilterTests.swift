//
//  HomeModelFilterTests.swift
//  damusTests
//
//  Created by Copilot on 2026-05-11.
//

import XCTest
@testable import damus

final class HomeModelFilterTests: XCTestCase {
    func testMakeSelfOnlyHomeFilterTargetsOnlyCurrentUser() {
        let pubkey = Pubkey(hex: "760f108754eb415561239d4079e71766d87e23f7e71c8e5b00d759e54dd8d082")!
        let kinds: [NostrKind] = [.text, .longform, .boost, .highlight]

        let filter = makeSelfOnlyHomeFilter(homeFilterKinds: kinds, pubkey: pubkey)

        XCTAssertEqual(filter.kinds, kinds)
        XCTAssertEqual(filter.authors, [pubkey])
        XCTAssertEqual(filter.limit, 500)
    }
}
