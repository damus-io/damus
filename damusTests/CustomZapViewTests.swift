//
//  CustomZapViewTests.swift
//  damusTests
//
//  Created by Terry Yiu on 4/29/23.
//

import XCTest
@testable import damus

final class CustomZapViewTests: XCTestCase {

    let enUsLocale = Locale(identifier: "en-US")

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSatsString() throws {
        XCTAssertEqual(satsString(0, locale: enUsLocale), "sats")
        XCTAssertEqual(satsString(1, locale: enUsLocale), "sat")
        XCTAssertEqual(satsString(2, locale: enUsLocale), "sats")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            for count in 1...10 {
                XCTAssertNoThrow(satsString(count, locale: $0))
            }
        }
    }

}
