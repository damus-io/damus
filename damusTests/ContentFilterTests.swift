//
//  ContentFilterTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-16.
//

import XCTest
@testable import damus

final class ContentFilterTests: XCTestCase {

    func test_event_has_nsfw_tag_lowercase() throws {
        let ev = NostrEvent(content: "tagged", keypair: test_keypair, tags: [["t", "nsfw"]])!
        XCTAssertTrue(event_has_nsfw_tag(ev))
    }

    func test_event_has_nsfw_tag_uppercase() throws {
        let ev = NostrEvent(content: "tagged", keypair: test_keypair, tags: [["t", "NSFW"]])!
        XCTAssertTrue(event_has_nsfw_tag(ev))
    }

    func test_event_has_nsfw_tag_mixed_case() throws {
        let ev = NostrEvent(content: "tagged", keypair: test_keypair, tags: [["t", "Nsfw"]])!
        XCTAssertTrue(event_has_nsfw_tag(ev))
    }

    func test_event_without_nsfw_tag() throws {
        let ev = NostrEvent(content: "clean", keypair: test_keypair, tags: [["t", "art"]])!
        XCTAssertFalse(event_has_nsfw_tag(ev))
    }

    func test_event_with_no_tags() throws {
        let ev = NostrEvent(content: "hello", keypair: test_keypair)!
        XCTAssertFalse(event_has_nsfw_tag(ev))
    }

    func test_nsfw_tag_filter_returns_false_for_nsfw() throws {
        let ev = NostrEvent(content: "tagged", keypair: test_keypair, tags: [["t", "nsfw"]])!
        XCTAssertFalse(nsfw_tag_filter(ev: ev))
    }

    func test_nsfw_tag_filter_returns_true_for_clean() throws {
        let ev = NostrEvent(content: "clean", keypair: test_keypair, tags: [["t", "art"]])!
        XCTAssertTrue(nsfw_tag_filter(ev: ev))
    }
}
