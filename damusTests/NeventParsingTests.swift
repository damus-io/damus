//
//  NeventParsingTests.swift
//  damusTests
//
//  Tests for nevent bech32 parsing
//

import XCTest
@testable import damus

final class NeventParsingTests: XCTestCase {

    /// Tests parsing of nevent with relay hints.
    /// Uses real nevent from user report for issue #3498.
    func testParseNeventWithRelayHints() throws {
        let neventString = "nevent1qqs94uyk9npgwmu3xumhc7wqfr8qknqaex98d9r9y09h5ldyjf57hkqpz3mhxue69uhhyetvv9ujuerpd46hxtnfduq3vamnwvaz7tmjv4kxz7fwwpexjmtpdshxuet5qgsr9cvzwc652r4m83d86ykplrnm9dg5gwdvzzn8ameanlvut35wy3grqsqqqqqpgdvecc"

        guard let parsed = Bech32Object.parse(neventString) else {
            XCTFail("Failed to parse nevent string")
            return
        }

        guard case .nevent(let nevent) = parsed else {
            XCTFail("Parsed object is not an nevent")
            return
        }

        // Verify parsing succeeded and extracted components
        XCTAssertNotNil(nevent.noteid, "Should have note ID")
        XCTAssertEqual(nevent.noteid.hex().count, 64, "Note ID should be 32 bytes (64 hex chars)")

        // This nevent has relay hints - verify they're extracted
        XCTAssertFalse(nevent.relays.isEmpty, "Should have relay hints")
    }
}
