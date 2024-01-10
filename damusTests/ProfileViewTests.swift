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
        let pk1 = test_pubkey
        let pk2 = test_pubkey_2
        let pk3 = Pubkey(hex: "b42e44b555013239a0d5dcdb09ebde0857cd8a5a57efbba5a2b6ac78833cb9f0")!
        let pk4 = Pubkey(hex: "cc590e46363d0fa66bb27081368d01f169b8ffc7c614629d4e9eef6c88b38670")!
        let pk5 = Pubkey(hex: "f2aa579bb998627e04a8f553842a09446360c9d708c6141dd119c479f6ab9d29")!

        let ndb = Ndb(path: Ndb.db_path)!

        let damus_name = "17ldvg64:nq5mhr77"
        XCTAssertEqual(followedByString([pk1], ndb: ndb, locale: enUsLocale), "Followed by \(damus_name)")
        XCTAssertEqual(followedByString([pk1, pk2], ndb: ndb, locale: enUsLocale), "Followed by \(damus_name) & 1rppft3m:4qxhsgnj")
        XCTAssertEqual(followedByString([pk1, pk2, pk3], ndb: ndb, locale: enUsLocale), "Followed by \(damus_name), 1rppft3m:4qxhsgnj & 1kshyfd2:cq04aze0")
        XCTAssertEqual(followedByString([pk1, pk2, pk3, pk4,], ndb: ndb, locale: enUsLocale), "Followed by \(damus_name), 1rppft3m:4qxhsgnj, 1kshyfd2:cq04aze0 & 1 other")
        XCTAssertEqual(followedByString([pk1, pk2, pk3, pk4, pk5], ndb: ndb, locale: enUsLocale), "Followed by \(damus_name), 1rppft3m:4qxhsgnj, 1kshyfd2:cq04aze0 & 2 others")

        let pubkeys = [pk1, pk2, pk3, pk4, pk5, pk1, pk2, pk3, pk4, pk5]
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            for count in 1...10 {
                XCTAssertNoThrow(followedByString(pubkeys.prefix(count).map { $0 }, ndb: ndb, locale: $0))
            }
        }
    }

}
