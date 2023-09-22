//
//  EventGroupViewTests.swift
//  damusTests
//
//  Created by Terry Yiu on 2/26/23.
//

import XCTest
@testable import damus

final class EventGroupViewTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testEventAuthorName() {
        let damusState = test_damus_state
        XCTAssertEqual(event_author_name(profiles: damusState.profiles, pubkey: test_pubkey), "damus")
        XCTAssertEqual(event_author_name(profiles: damusState.profiles, pubkey: test_pubkey_2), "1rppft3m:4qxhsgnj")
        XCTAssertEqual(event_author_name(profiles: damusState.profiles, pubkey: ANON_PUBKEY), "Anonymous")
    }

    func testEventGroupUniquePubkeys() {
        let damusState = test_damus_state

        let encodedPost = "{\"id\": \"8ba545ab96959fe0ce7db31bc10f3ac3aa5353bc4428dbf1e56a7be7062516db\",\"pubkey\": \"7e27509ccf1e297e1df164912a43406218f8bd80129424c3ef798ca3ef5c8444\",\"created_at\": 1677013417,\"kind\": 1,\"tags\": [],\"content\": \"hello\",\"sig\": \"93684f15eddf11f42afbdd81828ee9fc35350344d8650c78909099d776e9ad8d959cd5c4bff7045be3b0b255144add43d0feef97940794a1bc9c309791bebe4a\"}"

        let pk1 =
            hex_decode_pubkey("1723a4dcc6596d84472eb74d579114d8c46b533c81a0ac76620a7605d3ff76e0")!
        let pk2 =
            hex_decode_pubkey("08c43696702ba1d720e4564b4ad895efdc3716b37468fb288e585368950a428a")!
        let pk3 =
            hex_decode_pubkey("4e563600925231e9eb35a61842c2c6c19685aa8eefdfad076d6a3f853453a299")!

        let repost1 = NostrEvent(content: encodedPost, keypair: .just_pubkey(pk1), kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)!
        let repost2 = NostrEvent(content: encodedPost, keypair: .just_pubkey(pk2), kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)!
        let repost3 = NostrEvent(content: encodedPost, keypair: .just_pubkey(pk3), kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)!

        XCTAssertEqual(event_group_unique_pubkeys(profiles: damusState.profiles, group: .repost(EventGroup(events: []))), [])
        XCTAssertEqual(event_group_unique_pubkeys(profiles: damusState.profiles, group: .repost(EventGroup(events: [repost1]))), [pk1])
        XCTAssertEqual(event_group_unique_pubkeys(profiles: damusState.profiles, group: .repost(EventGroup(events: [repost1, repost2]))), [pk1, pk2])
        XCTAssertEqual(event_group_unique_pubkeys(profiles: damusState.profiles, group: .repost(EventGroup(events: [repost1, repost2, repost3]))), [pk1, pk2, pk3])
    }

    func testReactingToText() throws {
        let enUsLocale = Locale(identifier: "en-US")
        let damusState = test_damus_state

        let encodedPost = "{\"id\": \"8ba545ab96959fe0ce7db31bc10f3ac3aa5353bc4428dbf1e56a7be7062516db\",\"pubkey\": \"7e27509ccf1e297e1df164912a43406218f8bd80129424c3ef798ca3ef5c8444\",\"created_at\": 1677013417,\"kind\": 1,\"tags\": [],\"content\": \"hello\",\"sig\": \"93684f15eddf11f42afbdd81828ee9fc35350344d8650c78909099d776e9ad8d959cd5c4bff7045be3b0b255144add43d0feef97940794a1bc9c309791bebe4a\"}"

        let pk1_pk =
            hex_decode_pubkey("938afd5f44fdf293546767dcc024b4ec09b9df422fad10d577a846f88f56c8f5")!

        let pk2_pk =
            hex_decode_pubkey("6b9bb7acbcdf0458a81b9e6d29bb1e23ab9b5d288e9b7fa8cee8dedc9082a466")!

        let pk3_pk =
            hex_decode_pubkey("b9f00c1f12b0b7a2e3960565af7aba71da9678d90faeb60bc19813f3a28840de")!

        let pk1 = Keypair(pubkey: pk1_pk, privkey: nil)
        let pk2 = Keypair(pubkey: pk2_pk, privkey: nil)
        let pk3 = Keypair(pubkey: pk3_pk, privkey: nil)

        let repost1 = NostrEvent(content: encodedPost, keypair: pk1, kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)!
        let repost2 = NostrEvent(content: encodedPost, keypair: pk2, kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)!
        let repost3 = NostrEvent(content: encodedPost, keypair: pk3, kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)!

        XCTAssertEqual(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [])), ev: test_note, pubkeys: [], locale: enUsLocale), "??")
        XCTAssertEqual(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1])), ev: test_note, pubkeys: [pk1.pubkey], locale: enUsLocale), "1jw906h6:6saq3vx4 reposted a note you were tagged in")
        XCTAssertEqual(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1, repost2])), ev: test_note, pubkeys: [pk1.pubkey, pk2.pubkey], locale: enUsLocale), "1jw906h6:6saq3vx4 and 1dwdm0t9:nqtnamhd reposted a note you were tagged in")
        XCTAssertEqual(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1, repost2, repost2])), ev: test_note, pubkeys: [pk1.pubkey, pk2.pubkey, pk3.pubkey], locale: enUsLocale), "1jw906h6:6saq3vx4 and 2 others reposted a note you were tagged in")

        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            XCTAssertNoThrow(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [])), ev: test_note, pubkeys: [], locale: $0), "??")
            XCTAssertNoThrow(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1])), ev: test_note, pubkeys: [pk1.pubkey], locale: $0))
            XCTAssertNoThrow(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1, repost2])), ev: test_note, pubkeys: [pk1.pubkey, pk2.pubkey], locale: $0))
            XCTAssertNoThrow(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1, repost2, repost3])), ev: test_note, pubkeys: [pk1.pubkey, pk2.pubkey, pk3.pubkey], locale: $0))
        }
    }

}
