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
        // Empty string -> URL(string: "") returns nil -> robohash fallback
        let url = resolve_profile_picture_url(picture: "", pubkey: test_pubkey)
        XCTAssertTrue(url.absoluteString.contains("robohash.org"),
                       "empty string should fall back to robohash")
    }

    /// This is the exact bug scenario from the crash (issue #3141).
    ///
    /// The old code used `Optional.map` which produces `URL??`:
    ///   profile?.picture.map { URL(string: $0) }
    /// When picture is Some(""), the result is `.some(nil)`.
    /// The `??` operator sees `.some(nil)` as non-nil, takes the left branch,
    /// yields `nil`, and `!` crashes.
    ///
    /// The fix uses `flatMap` which collapses `URL??` -> `URL?`, so `.some(nil)`
    /// becomes `nil` and the robohash fallback fires correctly.
    func testResolveWithPresentButUnparseablePicture_ExactCrashScenario() throws {
        let picture: String? = ""
        let url = resolve_profile_picture_url(picture: picture, pubkey: test_pubkey)
        XCTAssertTrue(url.absoluteString.contains("robohash.org"),
                       "present-but-empty picture must fall through to robohash, not crash")

        // Verify the old pattern WOULD produce the double-optional trap:
        let oldResult: URL?? = picture.map { URL(string: $0) }
        XCTAssertNotNil(oldResult, "Optional.map wraps nil URL in .some — the double-optional trap")
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

    // MARK: - get_profile_url (main-app wrapper that delegates to resolve_)

    func testGetProfileUrlDelegatesToResolve() throws {
        let validPic = "https://example.com/avatar.png"
        let url = get_profile_url(picture: validPic, pubkey: test_pubkey, profiles: profiles)
        XCTAssertEqual(url.absoluteString, validPic)

        let nilUrl = get_profile_url(picture: nil, pubkey: test_pubkey, profiles: profiles)
        XCTAssertTrue(nilUrl.absoluteString.contains("robohash.org"))
    }
}
