//
//  ProfilePictureURLTests.swift
//  damusTests
//
//  Tests for profile picture URL resolution and robohash fallback logic.
//  Exercises resolve_profile_picture_url() — the shared function used by
//  both the main app (ProfilePicView) and the notification extension.
//

import XCTest
@testable import damus

class ProfilePictureURLTests: XCTestCase {

    let ndb = Ndb.test
    lazy var profiles = Profiles(ndb: ndb)

    // MARK: - robohash

    func testRobohashProducesValidURL() throws {
        let urlString = robohash(test_pubkey)
        XCTAssertNotNil(URL(string: urlString), "robohash output should be a valid URL")
    }

    func testRobohashContainsPubkeyHex() throws {
        let hex = test_pubkey.hex()
        let urlString = robohash(test_pubkey)
        XCTAssertTrue(urlString.contains(hex), "robohash URL should contain the pubkey hex")
    }

    // MARK: - resolve_profile_picture_url (the actual crash-fix function)

    func testResolveWithValidPicture() throws {
        let url = resolve_profile_picture_url(picture: "https://example.com/avatar.png", pubkey: test_pubkey)
        XCTAssertEqual(url.absoluteString, "https://example.com/avatar.png")
    }

    func testResolveWithNilPicture() throws {
        let url = resolve_profile_picture_url(picture: nil, pubkey: test_pubkey)
        XCTAssertTrue(url.absoluteString.contains("robohash.org"))
        XCTAssertTrue(url.absoluteString.contains(test_pubkey.hex()))
    }

    func testResolveWithEmptyString() throws {
        // Empty string → URL(string: "") returns nil → robohash fallback
        let url = resolve_profile_picture_url(picture: "", pubkey: test_pubkey)
        XCTAssertTrue(url.absoluteString.contains("robohash.org"),
                       "empty string should fall back to robohash")
    }

    /// This is the exact bug scenario from the crash.
    ///
    /// The old code used `Optional.map` which produces `URL??`:
    ///   profile?.picture.map { URL(string: $0) }
    /// When picture is Some("") or Some(invalid), the result is `.some(nil)`.
    /// The `??` operator sees `.some(nil)` as non-nil, takes the left branch,
    /// yields `nil`, and `!` crashes.
    ///
    /// The fix uses `flatMap` which collapses `URL??` → `URL?`, so `.some(nil)`
    /// becomes `nil` and the robohash fallback fires correctly.
    func testResolveWithPresentButUnparseablePicture_ExactCrashScenario() throws {
        // Simulate: profile exists, profile.picture is "" (present but empty)
        // Old code: Optional.some("").map { URL(string: $0) } → Optional.some(nil) → crash on !
        // New code: Optional.some("").flatMap(URL.init(string:)) → nil → robohash
        let picture: String? = ""
        let url = resolve_profile_picture_url(picture: picture, pubkey: test_pubkey)
        XCTAssertTrue(url.absoluteString.contains("robohash.org"),
                       "present-but-empty picture must fall through to robohash, not crash")

        // Verify the old pattern WOULD produce the double-optional trap:
        let oldResult: URL?? = picture.map { URL(string: $0) }
        // oldResult is .some(nil) — this is what caused the crash
        XCTAssertNotNil(oldResult, "Optional.map wraps nil URL in .some — the double-optional trap")
        // Unwrap the outer optional — the inner value is nil (would crash with !)
        if case .some(let inner) = oldResult {
            XCTAssertNil(inner, "Inner URL is nil — force unwrap here was the crash")
        }

        // Verify the new pattern (flatMap) collapses correctly:
        let newResult: URL? = picture.flatMap(URL.init(string:))
        XCTAssertNil(newResult, "flatMap collapses .some(nil) to nil — fallback fires")
    }

    func testResolveNeverCrashes() throws {
        let edgeCases: [String?] = [
            nil,
            "",
            " ",
            "\0",
            "://missing-scheme",
            "not a url",
            "https://valid.example.com/pic.jpg",
        ]

        for testCase in edgeCases {
            let url = resolve_profile_picture_url(picture: testCase, pubkey: test_pubkey)
            XCTAssertFalse(url.absoluteString.isEmpty,
                           "resolve_profile_picture_url must return valid URL for input: \(String(describing: testCase))")
        }
    }

    /// CRASH REPRODUCTION TEST: Before/After Demonstration
    ///
    /// This test demonstrates the exact crash from issue #3141 and proves the fix works.
    ///
    /// **To reproduce the crash:**
    /// 1. Uncomment the "OLD CODE" section below (lines marked with ❌)
    /// 2. Comment out the "NEW CODE" section (lines marked with ✅)
    /// 3. Run this test → it WILL CRASH with:
    ///    "Fatal error: Unexpectedly found nil while unwrapping an Optional value"
    ///
    /// **Production crash scenario:**
    /// - Nostr profile has empty or invalid picture field: `{"picture": ""}`
    /// - NotificationService receives notification from that user
    /// - Old code: `((picture.map { URL(string: $0) }) ?? fallback)!` → crash
    /// - Frequency: ~1/day on TestFlight build 1277 (issue #3560)
    ///
    /// **The fix:**
    /// - Use `flatMap` instead of `map` to collapse URL?? → URL?
    /// - Allows ?? fallback to fire correctly
    /// - Never force unwraps, always returns valid URL
    func testCrashReproduction_BeforeAfterFix() throws {
        // Simulate corrupted Nostr profile data
        let picture: String? = ""  // Empty string triggers the crash

        // ============================================================
        // ❌ OLD CODE (CRASHES) - Exact pattern from NotificationService.swift:63
        // ============================================================
        // Uncomment these lines to reproduce the crash:
        //
        // let oldResult = ((picture.map { URL(string: $0) })
        //                 ?? URL(string: "https://robohash.org/fallback"))!
        //                                                                  ^ CRASH HERE!
        // XCTAssertNotNil(oldResult)  // Never reaches here - crashes first
        //
        // Why it crashes:
        // 1. picture.map { URL(string: $0) } → .some(nil)  (URL?? double-optional trap!)
        // 2. ?? sees .some(nil) as non-nil, doesn't use fallback
        // 3. Result is nil
        // 4. ! force unwrap → CRASH

        // ============================================================
        // ✅ NEW CODE (SAFE) - Uses resolve_profile_picture_url with flatMap
        // ============================================================
        let newResult = resolve_profile_picture_url(picture: picture, pubkey: test_pubkey)

        // Assertions proving the fix works:
        XCTAssertTrue(newResult.absoluteString.contains("robohash.org"),
                      "Fix: Empty picture safely falls back to robohash")
        print("✅ PASS: Fix prevents crash, returns valid URL: \(newResult)")

        // ============================================================
        // DEMONSTRATION: Why old code creates the trap
        // ============================================================
        let step1: URL?? = picture.map { URL(string: $0) }
        XCTAssertNotNil(step1, "Step 1: map creates .some(nil) - outer optional is non-nil")

        if case .some(let inner) = step1 {
            XCTAssertNil(inner, "Step 2: Inner optional IS nil - this is the trap!")
        }

        let step2 = step1 ?? URL(string: "https://robohash.org/fallback")
        XCTAssertNil(step2, "Step 3: ?? doesn't fire (.some(nil) is not nil to ??), result is nil")

        // Step 4: Force unwrap would crash here (don't actually do it in test)
        print("Step 4: Old code would do step2! → CRASH (we don't execute this)")

        // ============================================================
        // DEMONSTRATION: Why new code (flatMap) is safe
        // ============================================================
        let safe1: URL? = picture.flatMap(URL.init(string:))
        XCTAssertNil(safe1, "flatMap collapses .some(nil) → nil (single optional, not double)")

        let safe2 = safe1 ?? URL(string: "https://robohash.org/fallback")
        XCTAssertNotNil(safe2, "?? sees nil, fires correctly, returns fallback")

        print("✅ flatMap fix: No double-optional trap, no crash, fallback works!")
    }

    // MARK: - get_profile_url (main-app wrapper that delegates to resolve_)

    func testGetProfileUrlDelegatesToResolve() throws {
        let validPic = "https://example.com/avatar.png"
        let url = get_profile_url(picture: validPic, pubkey: test_pubkey, profiles: profiles)
        XCTAssertEqual(url.absoluteString, validPic)

        let nilUrl = get_profile_url(picture: nil, pubkey: test_pubkey, profiles: profiles)
        XCTAssertTrue(nilUrl.absoluteString.contains("robohash.org"))
    }
}
