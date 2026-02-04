//
//  DamusPurpleAccountAttributesTests.swift
//  damusTests
//
//  Created by elsat on 2026-02-04.
//

import XCTest
@testable import damus

final class DamusPurpleAccountAttributesTests: XCTestCase {

    let testPubkeyHex = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"

    /// Tests parsing an account with no tenure attributes.
    func testParseAccountWithNoAttributes() throws {
        let json = """
        {
            "pubkey": "\(testPubkeyHex)",
            "created_at": 1700000000,
            "expiry": 1800000000,
            "subscriber_number": 42,
            "active": true,
            "attributes": {
                "member_for_more_than_one_year": false
            }
        }
        """

        guard let account = DamusPurple.Account.from(json_data: json.data(using: .utf8)!) else {
            XCTFail("Failed to parse account")
            return
        }

        XCTAssertFalse(account.attributes.contains(.memberForMoreThanOneYear))
        XCTAssertFalse(account.attributes.contains(.memberForMoreThanThreeYears))
    }

    /// Tests parsing an account with the one-year membership attribute.
    func testParseAccountWithOneYearAttribute() throws {
        let json = """
        {
            "pubkey": "\(testPubkeyHex)",
            "created_at": 1700000000,
            "expiry": 1800000000,
            "subscriber_number": 42,
            "active": true,
            "attributes": {
                "member_for_more_than_one_year": true
            }
        }
        """

        guard let account = DamusPurple.Account.from(json_data: json.data(using: .utf8)!) else {
            XCTFail("Failed to parse account")
            return
        }

        XCTAssertTrue(account.attributes.contains(.memberForMoreThanOneYear))
        XCTAssertFalse(account.attributes.contains(.memberForMoreThanThreeYears))
    }

    /// Tests parsing an account with the three-year membership attribute.
    func testParseAccountWithThreeYearAttribute() throws {
        let json = """
        {
            "pubkey": "\(testPubkeyHex)",
            "created_at": 1700000000,
            "expiry": 1800000000,
            "subscriber_number": 42,
            "active": true,
            "attributes": {
                "member_for_more_than_one_year": true,
                "member_for_more_than_three_years": true
            }
        }
        """

        guard let account = DamusPurple.Account.from(json_data: json.data(using: .utf8)!) else {
            XCTFail("Failed to parse account")
            return
        }

        XCTAssertTrue(account.attributes.contains(.memberForMoreThanOneYear))
        XCTAssertTrue(account.attributes.contains(.memberForMoreThanThreeYears))
    }

    /// Tests backward compatibility when the attributes field is null.
    func testParseAccountWithNullAttributes() throws {
        let json = """
        {
            "pubkey": "\(testPubkeyHex)",
            "created_at": 1700000000,
            "expiry": 1800000000,
            "subscriber_number": 42,
            "active": true,
            "attributes": null
        }
        """

        guard let account = DamusPurple.Account.from(json_data: json.data(using: .utf8)!) else {
            XCTFail("Failed to parse account")
            return
        }

        XCTAssertFalse(account.attributes.contains(.memberForMoreThanOneYear))
        XCTAssertFalse(account.attributes.contains(.memberForMoreThanThreeYears))
    }

    /// Tests backward compatibility when the attributes key is completely absent.
    func testParseAccountWithAbsentAttributesKey() throws {
        let json = """
        {
            "pubkey": "\(testPubkeyHex)",
            "created_at": 1700000000,
            "expiry": 1800000000,
            "subscriber_number": 42,
            "active": true
        }
        """

        guard let account = DamusPurple.Account.from(json_data: json.data(using: .utf8)!) else {
            XCTFail("Failed to parse account")
            return
        }

        XCTAssertFalse(account.attributes.contains(.memberForMoreThanOneYear))
        XCTAssertFalse(account.attributes.contains(.memberForMoreThanThreeYears))
    }
}
