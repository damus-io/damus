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

    func testFollowedByString() throws {
        let profiles = test_damus_state().profiles

        XCTAssertEqual(followedByString(["pk1"], profiles: profiles, locale: enUsLocale), "Followed by pk1:pk1")
        XCTAssertEqual(followedByString(["pk1", "pk2"], profiles: profiles, locale: enUsLocale), "Followed by pk1:pk1 & pk2:pk2")
        XCTAssertEqual(followedByString(["pk1", "pk2", "pk3"], profiles: profiles, locale: enUsLocale), "Followed by pk1:pk1, pk2:pk2 & pk3:pk3")
        XCTAssertEqual(followedByString(["pk1", "pk2", "pk3", "pk4",], profiles: profiles, locale: enUsLocale), "Followed by pk1:pk1, pk2:pk2, pk3:pk3 & 1 other")
        XCTAssertEqual(followedByString(["pk1", "pk2", "pk3", "pk4", "pk5"], profiles: profiles, locale: enUsLocale), "Followed by pk1:pk1, pk2:pk2, pk3:pk3 & 2 others")

        let pubkeys = ["pk1", "pk2", "pk3", "pk4", "pk5", "pk6", "pk7", "pk8", "pk9", "pk10"]
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            for count in 1...10 {
                XCTAssertNoThrow(followedByString(pubkeys.prefix(count).map { $0 }, profiles: profiles, locale: $0))
            }
        }
    }

}
