//
//  Benchmarking.swift
//  damusTests
//
//  Created by William Casarin on 3/6/25.
//

import Testing
import XCTest
@testable import damus

class BenchmarkingTests: XCTestCase {
    
    // Old regex-based implementations for comparison
    func trim_suffix_regex(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }
    
    func trim_prefix_regex(_ str: String) -> String {
        return str.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
    }
    
    // Test strings with different characteristics
    lazy var testStrings: [String] = [
        "   Hello World   ",                                // Simple whitespace
        "   \n\t  Hello World \n\t   ",                     // Mixed whitespace
        String(repeating: " ", count: 1000) + "Hello",      // Large prefix
        "Hello" + String(repeating: " ", count: 1000),      // Large suffix
        String(repeating: " ", count: 500) + "Hello" + String(repeating: " ", count: 500) // Both
    ]
    
    func testTrimSuffixRegexPerformance() throws {
        measure {
            for str in testStrings {
                _ = trim_suffix_regex(str)
            }
        }
    }
    
    func testTrimSuffixNewPerformance() throws {
        measure {
            for str in testStrings {
                _ = trim_suffix(str)
            }
        }
    }
    
    func testTrimPrefixRegexPerformance() throws {
        measure {
            for str in testStrings {
                _ = trim_prefix_regex(str)
            }
        }
    }
    
    func testTrimPrefixNewPerformance() throws {
        measure {
            for str in testStrings {
                _ = trim_prefix(str)
            }
        }
    }
    
    func testTrimFunctionCorrectness() throws {
        // Verify that both implementations produce the same results
        for str in testStrings {
            XCTAssertEqual(trim_suffix(str), trim_suffix_regex(str), "New trim_suffix implementation produces different results")
            XCTAssertEqual(trim_prefix(str), trim_prefix_regex(str), "New trim_prefix implementation produces different results")
        }
    }
}

