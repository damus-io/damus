//
//  TranslationTests.swift
//  damusTests
//
//  Created by KernelKind on 2/13/24.
//

import XCTest
@testable import damus

final class TranslationTests : XCTestCase {
    let translationStringDistanceCases = [
        ("test", "test ", false),
        ("wat", "what", false),
        ("wat's the wether like", "what's the weather like", true),
        ("GM GZY⚡️\n\redacted 🍆🦪🤙 https://video.nostr.build/7dadcc39e83cbc37c99fabb883314f29c169c1bd994f1d525bde6e9817facc85.mp4 ", "GM GZY⚡️\n\redacted 🍆🦪🤙 https://video.nostr.build/7dadcc39e83cbc37c99fabb883314f29c169c1bd994f1d525bde6e9817facc85.mp4", false),
        ("Fucking nostr forever typo’s lol 😂", "Fucking nostr forever typo's lol 😂", false),
        ("where's the library", "donde esta la libreria", true),
        ("In America", "En América", true)
    ]
    
    func testStringDistanceRequirements() {
        for (original, translated, expectedVal) in translationStringDistanceCases {
            XCTAssertEqual(translationMeetsStringDistanceRequirements(original: original, translated: translated), expectedVal)
        }
    }
    
    let levenshteinDistanceCases = [
        // (original string, mutated string, number of changes from original to mutated)
        ("hello", "hello", 0),    // No change
        ("123", "1234", 1),       // Addition at the end
        ("abcd", "abcde", 1),     // Addition at the end
        ("abc", "a", 2),          // Multiple deletions
        ("abcdef", "abc", 3),     // Multiple deletions
        ("2024", "2025", 1),      // Single substitution
        ("openai", "opnai", 1),   // Single deletion
        ("swift", "swiift", 1),   // Single addition
        ("language", "languag", 1), // Single deletion at the end
        ("example", "sxample", 1),  // Single substitution at the beginning
        ("distance", "d1stanc3", 2), // Substitutions
        ("python", "pyth0n", 1),    // Single substitution
        ("algorithm", "algor1thm", 1), // Single substitution in the middle
        ("implementation", "implemenation", 1), // Single deletion (typo)
        ("correction", "correctionn", 1),       // Single addition at the end
        ("levenshtein", "levenshtien", 2),      // Transposition
        ("threshold", "threshhold", 1),         // Single addition (double letter)
        ("functionality", "fuctionality", 1),   // Single deletion (common typo)
        ("assessment", "assesment", 1),         // Single deletion (common typo)
        ("performance", "performence", 1),      // Single substitution (common typo)
    ]
    
    func testLevenshteinDistance() {
        for (original, mutated, numChanges) in levenshteinDistanceCases {
            XCTAssertTrue(levenshteinDistanceIsGreaterThanOrEqualTo(from: original, to: mutated, threshold: numChanges))
            XCTAssertFalse(levenshteinDistanceIsGreaterThanOrEqualTo(from: original, to: mutated, threshold: numChanges+1))
        }
    }
}
