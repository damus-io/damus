//
//  LocalizationUtilTests.swift
//  damusTests
//
//  Created by Terry Yiu on 7/13/23.
//

import XCTest
@testable import damus

final class LocalizationUtilTests: XCTestCase {

    func testPluralizedString() throws {
        let enUsLocale = Locale(identifier: "en-US")

        // Test cases of the localization string key, and the expected en-US strings for a count of 0, 1, and 2.
        let keys = [
            ["followers_count", "Followers", "Follower", "Followers"],
            ["following_count", "Following", "Following", "Following"],
            ["imports_count", "Imports", "Import", "Imports"],
            ["hellthread_notification_settings", "Show notifications that mention more than 0 profiles", "Show notifications that mention more than 1 profile", "Show notifications that mention more than 2 profiles"],
            ["quoted_reposts_count", "Quotes", "Quote", "Quotes"],
            ["reactions_count", "Reactions", "Reaction", "Reactions"],
            ["relays_count", "Relays", "Relay", "Relays"],
            ["reposts_count", "Reposts", "Repost", "Reposts"],
            ["sats", "sats", "sat", "sats"],
            ["users_talking_about_it", "0 users talking about it", "1 user talking about it", "2 users talking about it"],
            ["word_count", "0 Words", "1 Word", "2 Words"],
            ["zaps_count", "Zaps", "Zap", "Zaps"]
        ]

        for key in keys {
            XCTAssertEqual(pluralizedString(key: key[0], count: 0, locale: enUsLocale), key[1])
            XCTAssertEqual(pluralizedString(key: key[0], count: 1, locale: enUsLocale), key[2])
            XCTAssertEqual(pluralizedString(key: key[0], count: 2, locale: enUsLocale), key[3])
            Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
                for count in 1...10 {
                    XCTAssertNoThrow(pluralizedString(key: key[0], count: count, locale: $0))
                }
            }
        }
    }

}
