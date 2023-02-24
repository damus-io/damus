//
//  FormatTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-01-17.
//

import XCTest
@testable import damus

final class FormatTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testAbbrevSatsFormat() throws {
        XCTAssertEqual(format_msats_abbrev(1_000_000 * 1000), "1m")
        XCTAssertEqual(format_msats_abbrev(1_100_000 * 1000), "1.1m")
        XCTAssertEqual(format_msats_abbrev(100_000_000 * 1000), "100m")
        XCTAssertEqual(format_msats_abbrev(1000 * 1000), "1k")
        XCTAssertEqual(format_msats_abbrev(1500 * 1000), "1.5k")
        XCTAssertEqual(format_msats_abbrev(1595 * 1000), "1.5k")
        XCTAssertEqual(format_msats_abbrev(100 * 1000), "100")
        XCTAssertEqual(format_msats_abbrev(0), "0")
        XCTAssertEqual(format_msats_abbrev(100_000_000 * 1000), "100m")
        XCTAssertEqual(format_msats_abbrev(999 * 1000), "999")
        XCTAssertEqual(format_msats_abbrev(999), "0.999")
        XCTAssertEqual(format_msats_abbrev(1), "0.001")
        XCTAssertEqual(format_msats_abbrev(1000), "1")
    }

    func testFormatMsats() throws {
        let enUsLocale = Locale(identifier: "en-US")
        XCTAssertEqual(format_msats(0, locale: enUsLocale), "0 sats")
        XCTAssertEqual(format_msats(1, locale: enUsLocale), "0.001 sats")
        XCTAssertEqual(format_msats(1000, locale: enUsLocale), "1 sat")
        XCTAssertEqual(format_msats(1001, locale: enUsLocale), "1.001 sats")
        XCTAssertEqual(format_msats(2000, locale: enUsLocale), "2 sats")
        XCTAssertEqual(format_msats(123456789, locale: enUsLocale), "123,456.789 sats")
        // Sanity check that function call does not throw in any supported locale as the string format accepts arguments, and a mismatched format in any one of the locales could break the app.
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            XCTAssertNoThrow(format_msats(0, locale: $0))
            XCTAssertNoThrow(format_msats(1, locale: $0))
            XCTAssertNoThrow(format_msats(1000, locale: $0))
            XCTAssertNoThrow(format_msats(1001, locale: $0))
            XCTAssertNoThrow(format_msats(2000, locale: $0))
            XCTAssertNoThrow(format_msats(123456789, locale: $0))
        }
    }

}
