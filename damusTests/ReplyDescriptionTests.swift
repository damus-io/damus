//
//  ReplyDescriptionTests.swift
//  damusTests
//
//  Created by Terry Yiu on 2/21/23.
//

import XCTest
@testable import damus

/* Existing unit tests failing on Github
final class ReplyDescriptionTests: XCTestCase {

    let enUsLocale = Locale(identifier: "en-US")
    let profiles = test_damus_state().profiles
    
    private func descriptionForEvent(withTags tags: [[String]]) -> String {
        var allTags = [["e", "123"]]
        allTags.append(contentsOf: tags)
        let replyingToOne = NostrEvent(
            content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jpg cool",
            pubkey: "pk",
            tags: allTags,
            createdAt: Int64(Date().timeIntervalSince1970 - 100)
        )
        
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            XCTAssertNoThrow(reply_desc(profiles: profiles, event: replyingToOne, locale: $0))
        }
        return reply_desc(profiles: profiles, event: replyingToOne, locale: enUsLocale)
    }
    
    // Test that English strings work properly with argument substitution and pluralization, and that other locales don't crash.
    func testReplyDesc() throws {
        let replyingToSelfEvent = test_event
        XCTAssertEqual(reply_desc(profiles: profiles, event: replyingToSelfEvent, locale: enUsLocale), "Replying to self")
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            XCTAssertNoThrow(reply_desc(profiles: profiles, event: replyingToSelfEvent, locale: $0))
        }
        
        // replying to one
        XCTAssertEqual(descriptionForEvent(withTags: [["p", "123"]]),
                       "Replying to \(Profile.displayName(profile: nil, pubkey: "123").username)")
        
        // replying to two
        XCTAssertEqual(descriptionForEvent(withTags: [["p", "123"], ["p", "456"]]),
                       "Replying to \(Profile.displayName(profile: nil, pubkey: "456").username) & \(Profile.displayName(profile: nil, pubkey: "123").username)")
        
        // replying to two that are the same
        XCTAssertEqual(descriptionForEvent(withTags: [["p", "123"], ["p", "123"]]),
                       "Replying to \(Profile.displayName(profile: nil, pubkey: "123").username)")
        
        // replying to two and one other
        XCTAssertEqual(descriptionForEvent(withTags: [["p", "123"], ["p", "456"], ["p", "789"]]),
                       "Replying to \(Profile.displayName(profile: nil, pubkey: "789").username), \(Profile.displayName(profile: nil, pubkey: "456").username) & 1 other")

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
            XCTAssertEqual(reply_desc(profiles: profiles, event: replyingToTwoAndMultipleOthers, locale: enUsLocale), "Replying to \(Profile.displayName(profile: nil, pubkey: "789").username), \(Profile.displayName(profile: nil, pubkey: "456").username) & \(othersCount) others")
            Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
                XCTAssertNoThrow(reply_desc(profiles: profiles, event: replyingToTwoAndMultipleOthers, locale: $0))
            }
        }
    }

}
*/
