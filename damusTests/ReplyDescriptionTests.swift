//
//  ReplyDescriptionTests.swift
//  damusTests
//
//  Created by Terry Yiu on 2/21/23.
//

import XCTest
@testable import damus

final class ReplyDescriptionTests: XCTestCase {

    let enUsLocale = Locale(identifier: "en-US")

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // Test that English strings work properly with argument substitution and pluralization, and that other locales don't crash.
    func testReplyDesc() throws {
        let profiles = test_damus_state().profiles

        let replyingToSelfEvent = test_event
        XCTAssertEqual(reply_desc(profiles: profiles, event: replyingToSelfEvent, locale: enUsLocale), "Replying to self")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            XCTAssertNoThrow(reply_desc(profiles: profiles, event: replyingToSelfEvent, locale: $0))
        }

        let replyingToOne = NostrEvent(
            content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jpg cool",
            pubkey: "pk",
            tags: [["e", "123"], ["p", "123"]],
            createdAt: Int64(Date().timeIntervalSince1970 - 100)
        )
        XCTAssertEqual(reply_desc(profiles: profiles, event: replyingToOne, locale: enUsLocale), "Replying to \(Profile.displayName(profile: nil, pubkey: "123"))")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            XCTAssertNoThrow(reply_desc(profiles: profiles, event: replyingToOne, locale: $0))
        }

        let replyingToTwo = NostrEvent(
            content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jpg cool",
            pubkey: "pk",
            tags: [["e", "123"], ["p", "123"], ["p", "456"]],
            createdAt: Int64(Date().timeIntervalSince1970 - 100)
        )
        XCTAssertEqual(reply_desc(profiles: profiles, event: replyingToTwo, locale: enUsLocale), "Replying to \(Profile.displayName(profile: nil, pubkey: "456")) & \(Profile.displayName(profile: nil, pubkey: "123"))")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            XCTAssertNoThrow(reply_desc(profiles: profiles, event: replyingToTwo, locale: $0))
        }

        let replyingToTwoAndOneOther = NostrEvent(
            content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jpg cool",
            pubkey: "pk",
            tags: [["e", "123"], ["p", "123"], ["p", "456"], ["p", "789"]],
            createdAt: Int64(Date().timeIntervalSince1970 - 100)
        )
        XCTAssertEqual(reply_desc(profiles: profiles, event: replyingToTwoAndOneOther, locale: enUsLocale), "Replying to \(Profile.displayName(profile: nil, pubkey: "789")), \(Profile.displayName(profile: nil, pubkey: "456")) & 1 other")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            XCTAssertNoThrow(reply_desc(profiles: profiles, event: replyingToTwoAndOneOther, locale: $0))
        }

        for othersCount in 2...10 {
            var tags: [[String]] = [["e", "123"]]
            for i in 1...othersCount {
                tags.append(["p", "\(i)"])
            }
            tags.append(["p", "456"])
            tags.append(["p", "789"])

            let replyingToTwoAndMultipleOthers = NostrEvent(
                content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jpg cool",
                pubkey: "pk",
                tags: tags,
                createdAt: Int64(Date().timeIntervalSince1970 - 100)
            )
            XCTAssertEqual(reply_desc(profiles: profiles, event: replyingToTwoAndMultipleOthers, locale: enUsLocale), "Replying to \(Profile.displayName(profile: nil, pubkey: "789")), \(Profile.displayName(profile: nil, pubkey: "456")) & \(othersCount) others")
            Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
                XCTAssertNoThrow(reply_desc(profiles: profiles, event: replyingToTwoAndMultipleOthers, locale: $0))
            }
        }
    }

}
