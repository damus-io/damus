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

    @MainActor
    private func makeProfileEvent(content: String, tags: [[String]], keypair: Keypair = test_keypair) -> NostrEvent {
        guard let event = NostrEvent(content: content, keypair: keypair, tags: tags) else {
            XCTFail("Expected test event creation to succeed")
            fatalError("Failed to create test event")
        }
        return event
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testOwnProfileBypassesNsfwAndHashtagFilters() throws {
        let damusState = generate_test_damus_state(mock_profile_info: nil)
        damusState.settings.hide_nsfw_tagged_content = true
        damusState.settings.hide_hashtag_spam = true
        damusState.settings.max_hashtags = 1

        let ownNsfwEvent = makeProfileEvent(content: "hello #nsfw", tags: [["t", "nsfw"]])
        let ownHashtagSpamEvent = makeProfileEvent(content: "#one #two", tags: [["t", "one"], ["t", "two"]])
        let otherKeypair = generate_new_keypair().to_keypair()
        let otherNsfwEvent = makeProfileEvent(content: "hello #nsfw", tags: [["t", "nsfw"]], keypair: otherKeypair)
        let otherHashtagSpamEvent = makeProfileEvent(content: "#one #two", tags: [["t", "one"], ["t", "two"]], keypair: otherKeypair)

        let filters = ContentFilters.defaults(damus_state: damusState)
        let combinedFilter = ContentFilters(filters: filters)

        XCTAssertTrue(combinedFilter.filter(ev: ownNsfwEvent))
        XCTAssertTrue(combinedFilter.filter(ev: ownHashtagSpamEvent))
        XCTAssertFalse(combinedFilter.filter(ev: otherNsfwEvent))
        XCTAssertFalse(combinedFilter.filter(ev: otherHashtagSpamEvent))
    }

    func testFollowedByString() throws {
        let pk1 = test_pubkey
        let pk2 = test_pubkey_2
        let pk3 = Pubkey(hex: "b42e44b555013239a0d5dcdb09ebde0857cd8a5a57efbba5a2b6ac78833cb9f0")!
        let pk4 = Pubkey(hex: "cc590e46363d0fa66bb27081368d01f169b8ffc7c614629d4e9eef6c88b38670")!
        let pk5 = Pubkey(hex: "f2aa579bb998627e04a8f553842a09446360c9d708c6141dd119c479f6ab9d29")!

        let ndb = Ndb(path: Ndb.db_path)!

        let damus_name = "npub17ldv...hr77"
        XCTAssertEqual(followedByString([pk1], ndb: ndb, locale: enUsLocale), "Followed by \(damus_name)")
        XCTAssertEqual(followedByString([pk1, pk2], ndb: ndb, locale: enUsLocale), "Followed by \(damus_name) & npub1rppf...sgnj")
        XCTAssertEqual(followedByString([pk1, pk2, pk3], ndb: ndb, locale: enUsLocale), "Followed by \(damus_name), npub1rppf...sgnj & npub1kshy...aze0")
        XCTAssertEqual(followedByString([pk1, pk2, pk3, pk4,], ndb: ndb, locale: enUsLocale), "Followed by \(damus_name), npub1rppf...sgnj, npub1kshy...aze0 & 1 other")
        XCTAssertEqual(followedByString([pk1, pk2, pk3, pk4, pk5], ndb: ndb, locale: enUsLocale), "Followed by \(damus_name), npub1rppf...sgnj, npub1kshy...aze0 & 2 others")

        let pubkeys = [pk1, pk2, pk3, pk4, pk5, pk1, pk2, pk3, pk4, pk5]
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            for count in 1...10 {
                XCTAssertNoThrow(followedByString(pubkeys.prefix(count).map { $0 }, ndb: ndb, locale: $0))
            }
        }
    }

}
