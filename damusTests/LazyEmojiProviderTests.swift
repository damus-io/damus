//
//  LazyEmojiProviderTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-03.
//

import XCTest
import EmojiKit
import EmojiPicker
@testable import damus

/// Checks that `LazyEmojiProvider` — which exists only to keep the expensive trie build
/// off the main thread at launch — answers exactly like the provider it wraps.
final class LazyEmojiProviderTests: XCTestCase {
    func testMatchesDefaultProvider() {
        let expected = DefaultEmojiProvider(showAllVariations: true)
        let lazy = LazyEmojiProvider(showAllVariations: true)

        XCTAssertEqual(lazy.isShowingAllVariations, expected.isShowingAllVariations)
        XCTAssertEqual(lazy.emojiCategories.count, expected.emojiCategories.count)
        XCTAssertEqual(lazy.variations.count, expected.variations.count)
        XCTAssertEqual(lazy.frequentlyUsedEmojis, expected.frequentlyUsedEmojis)

        for query in ["smile", "heart", "thumbs", "🤙"] {
            XCTAssertEqual(
                lazy.find(query: query).map({ $0.value }),
                expected.find(query: query).map({ $0.value }),
                "search results differ for '\(query)'"
            )
            XCTAssertFalse(lazy.find(query: query).isEmpty, "expected results for '\(query)'")
        }

        XCTAssertEqual(
            lazy.variation(for: "👍", skinTone1: .mediumDark, skinTone2: .neutral)?.value,
            expected.variation(for: "👍", skinTone1: .mediumDark, skinTone2: .neutral)?.value
        )
    }

    func testSkinTonePreferencesRoundTrip() {
        let provider = LazyEmojiProvider(showAllVariations: true)
        let original = (provider.skinTone1, provider.skinTone2)
        defer {
            provider.skinTone1 = original.0
            provider.skinTone2 = original.1
        }

        provider.skinTone1 = .dark
        provider.skinTone2 = .light
        XCTAssertEqual(provider.skinTone1, .dark)
        XCTAssertEqual(provider.skinTone2, .light)

        // The wrapped provider is shared, so a second wrapper sees the same preferences.
        XCTAssertEqual(LazyEmojiProvider(showAllVariations: true).skinTone1, .dark)
    }
}
