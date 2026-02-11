#!/usr/bin/env swift
//
//  crash_reproduction_demo_FIXED.swift
//  Demonstrates the fix for PR #3611
//
//  Shows that flatMap prevents the double-optional trap and crash.
//
//  Usage:
//    swift damusTests/crash_reproduction_demo_FIXED.swift
//
//  Expected output:
//    - No crash
//    - Fallback fires correctly
//    - Returns valid robohash URL
//

import Foundation

print("======================================================================")
print("FIX DEMONSTRATION: flatMap Prevents Crash")
print("======================================================================")
print()

// Same scenario: corrupted profile data
let picture: String? = ""  // Empty string

print("SCENARIO: Profile has empty picture field")
print("  picture = \"\" (String?)")
print()

print("OLD CODE (would crash):")
print("  picture.map { URL(string: $0) } → URL?? (double optional)")
print("  Creates .some(nil) trap, ?? doesn't fire, force unwrap crashes")
print()

print("NEW CODE (safe):")
print("  picture.flatMap(URL.init(string:)) → URL? (single optional)")
print()

let step1: URL? = picture.flatMap(URL.init(string:))
print("  Step 1: flatMap collapses to single optional")
print("    Result: \(step1 as Any)")
print("    Type: URL? (not URL??)")
print()

let step2 = step1 ?? URL(string: "https://robohash.org/fallback")
print("  Step 2: ?? fires correctly")
print("    Result: \(step2 as Any)")
print("    Why: Single optional nil is seen by ??")
print()

let step3 = step2!
print("  Step 3: Safe to unwrap (always has fallback)")
print("    Result: \(step3)")
print()

print("✅ SUCCESS: No crash, fallback worked!")
print()
print("Why this fix works:")
print("  - flatMap: String? → URL? (not URL??)")
print("  - Single optional: ?? operator fires correctly")
print("  - Triple fallback: picture → robohash → constant")
print("  - Never force unwraps nil")
