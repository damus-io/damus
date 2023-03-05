//
//  ProfileViewTests.swift
//  damusTests
//
//  Created by Terry Yiu on 2/24/23.
//

import XCTest
@testable import damus

final class ProfileViewTests: XCTestCase {

    let enUsLocale = Locale(identifier: "en-US")

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testFollowersCountString() throws {
        XCTAssertEqual(followersCountString(0, locale: enUsLocale), "Followers")
        XCTAssertEqual(followersCountString(1, locale: enUsLocale), "Follower")
        XCTAssertEqual(followersCountString(2, locale: enUsLocale), "Followers")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            for count in 1...10 {
                XCTAssertNoThrow(followersCountString(count, locale: $0))
            }
        }
    }

    func testRelaysCountString() throws {
        XCTAssertEqual(relaysCountString(0, locale: enUsLocale), "Relays")
        XCTAssertEqual(relaysCountString(1, locale: enUsLocale), "Relay")
        XCTAssertEqual(relaysCountString(2, locale: enUsLocale), "Relays")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            for count in 1...10 {
                XCTAssertNoThrow(relaysCountString(count, locale: $0))
            }
        }
    }

}
