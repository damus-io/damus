//
//  NIP05DomainTimelineHeaderViewTests.swift
//  damusTests
//
//  Created by Terry Yiu on 5/23/25.
//

import XCTest
@testable import damus

final class NIP05DomainTimelineHeaderViewTests: XCTestCase {

    let enUsLocale = Locale(identifier: "en-US")

    func testFriendsOfFriendsString() throws {
        let pk1 = test_pubkey
        let pk2 = test_pubkey_2
        let pk3 = Pubkey(hex: "b42e44b555013239a0d5dcdb09ebde0857cd8a5a57efbba5a2b6ac78833cb9f0")!
        let pk4 = Pubkey(hex: "cc590e46363d0fa66bb27081368d01f169b8ffc7c614629d4e9eef6c88b38670")!
        let pk5 = Pubkey(hex: "f2aa579bb998627e04a8f553842a09446360c9d708c6141dd119c479f6ab9d29")!

        let ndb = Ndb(path: Ndb.db_path)!

        let damus_name = "npub17ldv...hr77"
        XCTAssertEqual(friendsOfFriendsString([pk1], ndb: ndb, locale: enUsLocale), "Notes from \(damus_name)")
        XCTAssertEqual(friendsOfFriendsString([pk1, pk2], ndb: ndb, locale: enUsLocale), "Notes from \(damus_name) & npub1rppf...sgnj")
        XCTAssertEqual(friendsOfFriendsString([pk1, pk2, pk3], ndb: ndb, locale: enUsLocale), "Notes from \(damus_name), npub1rppf...sgnj & npub1kshy...aze0")
        XCTAssertEqual(friendsOfFriendsString([pk1, pk2, pk3, pk4,], ndb: ndb, locale: enUsLocale), "Notes from \(damus_name), npub1rppf...sgnj, npub1kshy...aze0 & 1 other in your trusted network")
        XCTAssertEqual(friendsOfFriendsString([pk1, pk2, pk3, pk4, pk5], ndb: ndb, locale: enUsLocale), "Notes from \(damus_name), npub1rppf...sgnj, npub1kshy...aze0 & 2 others in your trusted network")

        let pubkeys = [pk1, pk2, pk3, pk4, pk5, pk1, pk2, pk3, pk4, pk5]
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            for count in 1...10 {
                XCTAssertNoThrow(friendsOfFriendsString(pubkeys.prefix(count).map { $0 }, ndb: ndb, locale: $0))
            }
        }
    }

}
