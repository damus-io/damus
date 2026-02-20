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

    // MARK: - Decoding

    func testParseAccountWithDuration() throws {
        let duration: Double = 400 * 24 * 60 * 60
        let json = """
        {
            "pubkey": "\(testPubkeyHex)",
            "created_at": 1700000000,
            "expiry": 1800000000,
            "subscriber_number": 42,
            "active": true,
            "attributes": {
                "member_for_more_than_one_year": true,
                "active_membership_duration": \(duration)
            }
        }
        """

        let account = try XCTUnwrap(DamusPurple.Account.from(json_data: json.data(using: .utf8)!))
        XCTAssertEqual(account.active_membership_duration, duration)
    }

    func testBackwardCompatBooleanOnly() throws {
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

        let account = try XCTUnwrap(DamusPurple.Account.from(json_data: json.data(using: .utf8)!))
        XCTAssertTrue(account.active_membership_duration > DamusPurple.Account.one_year)
    }

    func testDurationOnlyNoBooleanField() throws {
        let duration: Double = 5 * 360 * 24 * 60 * 60
        let json = """
        {
            "pubkey": "\(testPubkeyHex)",
            "created_at": 1700000000,
            "expiry": 1800000000,
            "subscriber_number": 42,
            "active": true,
            "attributes": {
                "active_membership_duration": \(duration)
            }
        }
        """

        let account = try XCTUnwrap(DamusPurple.Account.from(json_data: json.data(using: .utf8)!))
        XCTAssertEqual(account.active_membership_duration, duration)
    }

    func testNullAttributesDefaultsToZero() throws {
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

        let account = try XCTUnwrap(DamusPurple.Account.from(json_data: json.data(using: .utf8)!))
        XCTAssertEqual(account.active_membership_duration, 0)
    }
}
