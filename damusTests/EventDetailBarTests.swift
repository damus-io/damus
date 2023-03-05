//
//  EventDetailBarTests.swift
//  damusTests
//
//  Created by Terry Yiu on 2/24/23.
//

import XCTest
@testable import damus

final class EventDetailBarTests: XCTestCase {

    let enUsLocale = Locale(identifier: "en-US")

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testRepostsCountString() throws {
        XCTAssertEqual(repostsCountString(0, locale: enUsLocale), "Reposts")
        XCTAssertEqual(repostsCountString(1, locale: enUsLocale), "Repost")
        XCTAssertEqual(repostsCountString(2, locale: enUsLocale), "Reposts")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            for count in 1...10 {
                XCTAssertNoThrow(repostsCountString(count, locale: $0))
            }
        }
    }

    func testReactionsCountString() throws {
        XCTAssertEqual(reactionsCountString(0, locale: enUsLocale), "Reactions")
        XCTAssertEqual(reactionsCountString(1, locale: enUsLocale), "Reaction")
        XCTAssertEqual(reactionsCountString(2, locale: enUsLocale), "Reactions")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            for count in 1...10 {
                XCTAssertNoThrow(reactionsCountString(count, locale: $0))
            }
        }
    }

    func testZapssCountString() throws {
        XCTAssertEqual(zapsCountString(0, locale: enUsLocale), "Zaps")
        XCTAssertEqual(zapsCountString(1, locale: enUsLocale), "Zap")
        XCTAssertEqual(zapsCountString(2, locale: enUsLocale), "Zaps")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            for count in 1...10 {
                XCTAssertNoThrow(zapsCountString(count, locale: $0))
            }
        }
    }

}
