//
//  DraftTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2025-01-15

import XCTest
@testable import damus

class DraftTests: XCTestCase {
    func testRoundtripNIP37Draft() {
        let test_note =
                NostrEvent(
                    content: "Test",
                    keypair: test_keypair_full.to_keypair(),
                    createdAt: UInt32(Date().timeIntervalSince1970 - 100)
                )!
        let draft = try! NIP37Draft(unwrapped_note: test_note, draft_id: "test", keypair: test_keypair_full)!
        XCTAssertEqual(draft.unwrapped_note, test_note)
    }
}
