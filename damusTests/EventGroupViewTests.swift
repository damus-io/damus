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
        let damusState = test_damus_state()
        XCTAssertEqual(event_author_name(profiles: damusState.profiles, pubkey: "pk1"), "pk1:pk1")
        XCTAssertEqual(event_author_name(profiles: damusState.profiles, pubkey: "pk2"), "pk2:pk2")
        XCTAssertEqual(event_author_name(profiles: damusState.profiles, pubkey: "anon"), "Anonymous")
    }

    func testEventGroupUniquePubkeys() {
        let damusState = test_damus_state()

        let encodedPost = "{\"id\": \"8ba545ab96959fe0ce7db31bc10f3ac3aa5353bc4428dbf1e56a7be7062516db\",\"pubkey\": \"7e27509ccf1e297e1df164912a43406218f8bd80129424c3ef798ca3ef5c8444\",\"created_at\": 1677013417,\"kind\": 1,\"tags\": [],\"content\": \"hello\",\"sig\": \"93684f15eddf11f42afbdd81828ee9fc35350344d8650c78909099d776e9ad8d959cd5c4bff7045be3b0b255144add43d0feef97940794a1bc9c309791bebe4a\"}"
        let repost1 = NostrEvent(id: "", content: encodedPost, pubkey: "pk1", kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)
        let repost2 = NostrEvent(id: "", content: encodedPost, pubkey: "pk2", kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)
        let repost3 = NostrEvent(id: "", content: encodedPost, pubkey: "pk3", kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)

        XCTAssertEqual(event_group_unique_pubkeys(profiles: damusState.profiles, group: .repost(EventGroup(events: []))), [])
        XCTAssertEqual(event_group_unique_pubkeys(profiles: damusState.profiles, group: .repost(EventGroup(events: [repost1]))), ["pk1"])
        XCTAssertEqual(event_group_unique_pubkeys(profiles: damusState.profiles, group: .repost(EventGroup(events: [repost1, repost2]))), ["pk1", "pk2"])
        XCTAssertEqual(event_group_unique_pubkeys(profiles: damusState.profiles, group: .repost(EventGroup(events: [repost1, repost2, repost3]))), ["pk1", "pk2", "pk3"])
    }

    func testReactingToText() throws {
        let enUsLocale = Locale(identifier: "en-US")
        let damusState = test_damus_state()

        let encodedPost = "{\"id\": \"8ba545ab96959fe0ce7db31bc10f3ac3aa5353bc4428dbf1e56a7be7062516db\",\"pubkey\": \"7e27509ccf1e297e1df164912a43406218f8bd80129424c3ef798ca3ef5c8444\",\"created_at\": 1677013417,\"kind\": 1,\"tags\": [],\"content\": \"hello\",\"sig\": \"93684f15eddf11f42afbdd81828ee9fc35350344d8650c78909099d776e9ad8d959cd5c4bff7045be3b0b255144add43d0feef97940794a1bc9c309791bebe4a\"}"
        let repost1 = NostrEvent(id: "", content: encodedPost, pubkey: "pk1", kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)
        let repost2 = NostrEvent(id: "", content: encodedPost, pubkey: "pk2", kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)
        let repost3 = NostrEvent(id: "", content: encodedPost, pubkey: "pk3", kind: NostrKind.boost.rawValue, tags: [], createdAt: 1)

        let nozaps = true
        XCTAssertEqual(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [])), ev: test_event, nozaps: nozaps, pubkeys: [], locale: enUsLocale), "??")
        XCTAssertEqual(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1])), ev: test_event, nozaps: nozaps, pubkeys: ["pk1"], locale: enUsLocale), "pk1:pk1 reposted a note you were tagged in")
        XCTAssertEqual(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1, repost2])), ev: test_event, nozaps: nozaps, pubkeys: ["pk1", "pk2"], locale: enUsLocale), "pk1:pk1 and pk2:pk2 reposted a note you were tagged in")
        XCTAssertEqual(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1, repost2, repost2])), ev: test_event, nozaps: nozaps, pubkeys: ["pk1", "pk2", "pk3"], locale: enUsLocale), "pk1:pk1 and 2 others reposted a note you were tagged in")

        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            XCTAssertNoThrow(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [])), ev: test_event, nozaps: nozaps, pubkeys: [], locale: $0), "??")
            XCTAssertNoThrow(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1])), ev: test_event, nozaps: nozaps, pubkeys: ["pk1"], locale: $0))
            XCTAssertNoThrow(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1, repost2])), ev: test_event, nozaps: nozaps, pubkeys: ["pk1", "pk2"], locale: $0))
            XCTAssertNoThrow(reacting_to_text(profiles: damusState.profiles, our_pubkey: damusState.pubkey, group: .repost(EventGroup(events: [repost1, repost2, repost3])), ev: test_event, nozaps: nozaps, pubkeys: ["pk1", "pk2", "pk3"], locale: $0))
        }
    }

}
