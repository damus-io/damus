//
//  RepostedTests.swift
//  damusTests
//
//  Created by Terry Yiu on 2/23/25.
//

import XCTest
@testable import damus

final class RepostedTests: XCTestCase {

    func testPeopleRepostedText() throws {
        let enUsLocale = Locale(identifier: "en-US")
        let damusState = test_damus_state
        let pubkey = test_pubkey

        // reposts must be greater than 0. Empty string is returned as a fallback if not.
        XCTAssertEqual(people_reposted_text(profiles: damusState.profiles, pubkey: pubkey, reposts: -1, locale: enUsLocale), "")
        XCTAssertEqual(people_reposted_text(profiles: damusState.profiles, pubkey: pubkey, reposts: 0, locale: enUsLocale), "")

        // Verify the English pluralization variations.
        XCTAssertEqual(people_reposted_text(profiles: damusState.profiles, pubkey: pubkey, reposts: 1, locale: enUsLocale), "17ldvg64:nq5mhr77 reposted")
        XCTAssertEqual(people_reposted_text(profiles: damusState.profiles, pubkey: pubkey, reposts: 2, locale: enUsLocale), "17ldvg64:nq5mhr77 and 1 other reposted")
        XCTAssertEqual(people_reposted_text(profiles: damusState.profiles, pubkey: pubkey, reposts: 3, locale: enUsLocale), "17ldvg64:nq5mhr77 and 2 others reposted")

        // Sanity check that the non-English translations are likely not malformed.
        Bundle.main.localizations.map { Locale(identifier: $0) }.forEach {
            // -1...11 covers a lot (but not all) pluralization rules for different languages.
            // However, it is good enough for a sanity check.
            for reposts in -1...11 {
                XCTAssertNoThrow(people_reposted_text(profiles: damusState.profiles, pubkey: pubkey, reposts: reposts, locale: $0))
            }
        }
    }

}
