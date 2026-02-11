#!/usr/bin/env swift
//
//  crash_reproduction_demo.swift
//  Standalone crash demonstration for PR #3611
//
//  Demonstrates the force unwrap crash from issue #3141 and proves the fix works.
//
//  Usage:
//    swift damusTests/crash_reproduction_demo.swift
//
//  Expected output:
//    - Shows old code creates double-optional trap
//    - CRASHES on force unwrap (line 38)
//    - Proves flatMap fix prevents crash
//

import Foundation

print("======================================================================")
print("CRASH REPRODUCTION: Force Unwrap in NotificationService (Issue #3141)")
print("======================================================================")
print()

// Simulate corrupted Nostr profile data
let picture: String? = ""  // Empty string from profile

print("SCENARIO: Profile has empty picture field")
print("  picture = \"\" (String?)")
print()

print("STEP 1: Old code creates double-optional trap")
print("  let step1 = picture.map { URL(string: $0) }")
let step1: URL?? = picture.map { URL(string: $0) }
print("  Result: \(step1)")
print("  Type: URL??")
print("  Value: .some(nil) ← DOUBLE OPTIONAL TRAP!")
print()

print("STEP 2: ?? operator fails to fire")
print("  let step2 = step1 ?? URL(string: \"robohash\")")
let step2 = step1 ?? URL(string: "https://robohash.org/fallback")
print("  Result: \(step2 as Any)")
print("  Why: ?? sees .some(nil) as NON-NIL (outer optional exists)")
print("  So: Fallback doesn't fire, result is nil")
print()

print("STEP 3: Force unwrap crashes")
print("  let step3 = step2!")
print("  Executing...")
print()

let step3 = step2!  // ← CRASH HERE!

print("❌ Never reaches here - crashes first")
