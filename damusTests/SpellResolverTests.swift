//
//  SpellResolverTests.swift
//  damusTests
//
//  Tests for SpellResolver: variable + timestamp resolution
//

import XCTest
@testable import damus

final class SpellResolverTests: XCTestCase {

    let now: UInt64 = 1_700_000_000

    lazy var context: SpellResolutionContext = {
        SpellResolutionContext(
            userPubkey: test_pubkey,
            contacts: [test_pubkey_2],
            now: now
        )
    }()

    // MARK: - Basic resolution

    func test_resolve_minimal_spell() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"]]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(resolved.filters.count, 1)
        XCTAssertEqual(resolved.filters.first?.kinds, [.text])
        XCTAssertNil(resolved.filters.first?.authors)
        XCTAssertEqual(resolved.command, .req)
    }

    func test_resolve_produces_ndb_filters() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["limit", "50"]]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(resolved.ndbFilters.count, 1)
        XCTAssertEqual(resolved.ndbFilters.count, resolved.filters.count)
    }

    func test_resolve_me_author() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["authors", "$me"]]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(resolved.filters.first?.authors, [test_pubkey])
    }

    func test_resolve_contacts_author() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["authors", "$contacts"]]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(resolved.filters.first?.authors, [test_pubkey_2])
    }

    func test_resolve_me_and_contacts_authors() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["authors", "$me", "$contacts"]]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(resolved.filters.first?.authors, [test_pubkey, test_pubkey_2])
    }

    // MARK: - Tag filter resolution

    func test_resolve_hashtag_filter() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["tag", "t", "bitcoin", "nostr"]]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(resolved.filters.first?.hashtag, ["bitcoin", "nostr"])
    }

    func test_resolve_p_tag_with_me_variable() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["tag", "p", "$me"]]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(resolved.filters.first?.pubkeys, [test_pubkey])
    }

    // MARK: - Timestamp resolution

    func test_resolve_relative_since() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["since", "7d"]]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        let expectedSince = UInt32(now - 7 * 86400)
        XCTAssertEqual(resolved.filters.first?.since, expectedSince)
    }

    func test_resolve_absolute_since() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["since", "1704067200"]]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(resolved.filters.first?.since, 1704067200)
    }

    // MARK: - Metadata pass-through

    func test_resolved_spell_carries_metadata() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [
                ["cmd", "COUNT"],
                ["k", "1"],
                ["search", "nostr dev"],
                ["relays", "wss://nos.lol/"],
                ["close-on-eose"]
            ]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(resolved.command, .count)
        XCTAssertEqual(resolved.search, "nostr dev")
        XCTAssertEqual(resolved.relays, ["wss://nos.lol/"])
        XCTAssertTrue(resolved.closeOnEose)
    }

    // MARK: - Error cases

    func test_reject_empty_contacts() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["authors", "$contacts"]]
        )!
        let spell = SpellEvent.parse(from: ev)!

        let emptyContext = SpellResolutionContext(
            userPubkey: test_pubkey,
            contacts: [],
            now: now
        )
        let result = SpellResolver.resolve(spell, context: emptyContext)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure")
            return
        }

        XCTAssertEqual(error, .emptyContacts)
    }

    // MARK: - Limit pass-through

    func test_resolve_limit() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["limit", "50"]]
        )!
        let spell = SpellEvent.parse(from: ev)!
        let result = SpellResolver.resolve(spell, context: context)

        guard case .success(let resolved) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(resolved.filters.first?.limit, 50)
    }
}
