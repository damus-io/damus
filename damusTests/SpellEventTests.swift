//
//  SpellEventTests.swift
//  damusTests
//
//  Tests for NIP-A7 spell parsing (kind:777)
//

import XCTest
@testable import damus

final class SpellEventTests: XCTestCase {

    // MARK: - SpellTimestamp parsing

    func test_parse_relative_timestamp_days() {
        let ts = SpellTimestamp.parse("7d")
        XCTAssertEqual(ts, .relative(SpellTimestamp.RelativeTime(amount: 7, unit: .days)))
    }

    func test_parse_relative_timestamp_hours() {
        let ts = SpellTimestamp.parse("24h")
        XCTAssertEqual(ts, .relative(SpellTimestamp.RelativeTime(amount: 24, unit: .hours)))
    }

    func test_parse_relative_timestamp_months() {
        let ts = SpellTimestamp.parse("1mo")
        XCTAssertEqual(ts, .relative(SpellTimestamp.RelativeTime(amount: 1, unit: .months)))
    }

    func test_parse_relative_timestamp_weeks() {
        let ts = SpellTimestamp.parse("2w")
        XCTAssertEqual(ts, .relative(SpellTimestamp.RelativeTime(amount: 2, unit: .weeks)))
    }

    func test_parse_absolute_timestamp() {
        let ts = SpellTimestamp.parse("1704067200")
        XCTAssertEqual(ts, .absolute(1704067200))
    }

    func test_parse_now_timestamp() {
        let ts = SpellTimestamp.parse("now")
        XCTAssertEqual(ts, .now)
    }

    func test_parse_invalid_timestamp() {
        let ts = SpellTimestamp.parse("invalid")
        XCTAssertNil(ts)
    }

    func test_resolve_relative_timestamp() {
        let ts = SpellTimestamp.relative(SpellTimestamp.RelativeTime(amount: 7, unit: .days))
        let now: UInt64 = 1_700_000_000
        let resolved = ts.resolve(now: now)
        XCTAssertEqual(resolved, now - 7 * 86400)
    }

    func test_resolve_now_timestamp() {
        let now: UInt64 = 1_700_000_000
        let resolved = SpellTimestamp.now.resolve(now: now)
        XCTAssertEqual(resolved, now)
    }

    // MARK: - SpellVariable parsing

    func test_parse_me_variable() {
        XCTAssertEqual(SpellVariable.parse("$me"), .me)
    }

    func test_parse_contacts_variable() {
        XCTAssertEqual(SpellVariable.parse("$contacts"), .contacts)
    }

    func test_parse_invalid_variable() {
        XCTAssertNil(SpellVariable.parse("$invalid"))
        XCTAssertNil(SpellVariable.parse("me"))
        XCTAssertNil(SpellVariable.parse("$ME"))
    }

    // MARK: - SpellValue parsing

    func test_parse_value_literal() {
        let val = SpellValue.parse("abc123")
        XCTAssertEqual(val, .literal("abc123"))
        XCTAssertFalse(val.isVariable)
    }

    func test_parse_value_variable() {
        let val = SpellValue.parse("$contacts")
        XCTAssertEqual(val, .variable(.contacts))
        XCTAssertTrue(val.isVariable)
    }

    // MARK: - SpellEvent parsing

    func test_parse_minimal_spell() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"]]
        )!
        let spell = SpellEvent.parse(from: ev)

        XCTAssertNotNil(spell)
        XCTAssertEqual(spell?.command, .req)
        XCTAssertEqual(spell?.kinds, [1])
        XCTAssertTrue(spell?.authors.isEmpty ?? false)
        XCTAssertNil(spell?.limit)
        XCTAssertNil(spell?.since)
        XCTAssertEqual(spell?.displayName, "Custom Feed")
    }

    func test_parse_bitcoin_contacts_spell() {
        let ev = NostrEvent(
            content: "Notes about Bitcoin from my contacts",
            keypair: test_keypair,
            kind: 777,
            tags: [
                ["cmd", "REQ"],
                ["name", "Bitcoin from contacts"],
                ["alt", "Spell: notes about Bitcoin from contacts"],
                ["k", "1"],
                ["authors", "$contacts"],
                ["tag", "t", "bitcoin"],
                ["since", "7d"],
                ["limit", "50"],
                ["t", "bitcoin"],
                ["t", "social"]
            ]
        )!
        let spell = SpellEvent.parse(from: ev)

        XCTAssertNotNil(spell)
        XCTAssertEqual(spell?.command, .req)
        XCTAssertEqual(spell?.kinds, [1])
        XCTAssertEqual(spell?.authors, [.variable(.contacts)])
        XCTAssertEqual(spell?.limit, 50)
        XCTAssertEqual(spell?.since, .relative(SpellTimestamp.RelativeTime(amount: 7, unit: .days)))
        XCTAssertEqual(spell?.name, "Bitcoin from contacts")
        XCTAssertEqual(spell?.alt, "Spell: notes about Bitcoin from contacts")
        XCTAssertEqual(spell?.topics, ["bitcoin", "social"])
        XCTAssertEqual(spell?.displayDescription, "Notes about Bitcoin from my contacts")
        XCTAssertTrue(spell?.requiresContacts ?? false)

        // Tag filter: ["tag", "t", "bitcoin"]
        XCTAssertEqual(spell?.tagFilters.count, 1)
        XCTAssertEqual(spell?.tagFilters.first?.letter, "t")
        XCTAssertEqual(spell?.tagFilters.first?.values, [.literal("bitcoin")])
    }

    func test_parse_mentions_spell() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [
                ["cmd", "REQ"],
                ["name", "Mentions"],
                ["alt", "Grimoire REQ spell"],
                ["k", "1"],
                ["k", "11"],
                ["k", "6"],
                ["k", "7"],
                ["tag", "p", "$me"],
                ["limit", "50"]
            ]
        )!
        let spell = SpellEvent.parse(from: ev)

        XCTAssertNotNil(spell)
        XCTAssertEqual(spell?.kinds, [1, 11, 6, 7])
        XCTAssertTrue(spell?.authors.isEmpty ?? false)
        XCTAssertEqual(spell?.tagFilters.count, 1)
        XCTAssertEqual(spell?.tagFilters.first?.letter, "p")
        XCTAssertEqual(spell?.tagFilters.first?.values, [.variable(.me)])
        XCTAssertTrue(spell?.hasVariables ?? false)
        XCTAssertFalse(spell?.requiresContacts ?? true)
    }

    func test_parse_me_and_contacts_authors() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [
                ["cmd", "REQ"],
                ["name", "Comments"],
                ["k", "20"],
                ["k", "22"],
                ["k", "24"],
                ["k", "1111"],
                ["authors", "$me", "$contacts"],
                ["tag", "t", "nature", "musicstr", "artnostr"],
                ["limit", "80"],
                ["since", "7d"]
            ]
        )!
        let spell = SpellEvent.parse(from: ev)

        XCTAssertNotNil(spell)
        XCTAssertEqual(spell?.authors, [.variable(.me), .variable(.contacts)])
        XCTAssertEqual(spell?.kinds, [20, 22, 24, 1111])
        XCTAssertTrue(spell?.requiresContacts ?? false)

        // Tag filter with multiple values
        XCTAssertEqual(spell?.tagFilters.first?.letter, "t")
        XCTAssertEqual(spell?.tagFilters.first?.values, [
            .literal("nature"), .literal("musicstr"), .literal("artnostr")
        ])
    }

    func test_parse_spell_with_relays() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [
                ["cmd", "REQ"],
                ["name", "Playlists from the Network"],
                ["k", "34139"],
                ["limit", "420"],
                ["relays", "wss://nos.lol/", "wss://relay.damus.io/"]
            ]
        )!
        let spell = SpellEvent.parse(from: ev)

        XCTAssertNotNil(spell)
        XCTAssertEqual(spell?.relays, ["wss://nos.lol/", "wss://relay.damus.io/"])
        XCTAssertFalse(spell?.hasVariables ?? true)
    }

    func test_parse_count_spell() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [
                ["cmd", "COUNT"],
                ["k", "1"],
                ["k", "6"],
                ["k", "7"],
                ["authors", "$me"],
                ["since", "1704067200"],
                ["close-on-eose"]
            ]
        )!
        let spell = SpellEvent.parse(from: ev)

        XCTAssertNotNil(spell)
        XCTAssertEqual(spell?.command, .count)
        XCTAssertEqual(spell?.kinds, [1, 6, 7])
        XCTAssertEqual(spell?.authors, [.variable(.me)])
        XCTAssertEqual(spell?.since, .absolute(1704067200))
        XCTAssertTrue(spell?.closeOnEose ?? false)
    }

    func test_parse_spell_with_search() {
        let ev = NostrEvent(
            content: "Search for Nostr dev discussions",
            keypair: test_keypair,
            kind: 777,
            tags: [
                ["cmd", "REQ"],
                ["k", "1"],
                ["search", "nostr development"],
                ["limit", "100"]
            ]
        )!
        let spell = SpellEvent.parse(from: ev)

        XCTAssertNotNil(spell)
        XCTAssertEqual(spell?.search, "nostr development")
        XCTAssertEqual(spell?.limit, 100)
    }

    func test_parse_contacts_in_tag_filter() {
        let ev = NostrEvent(
            content: "frens reporting frens",
            keypair: test_keypair,
            kind: 777,
            tags: [
                ["cmd", "REQ"],
                ["name", "Reports"],
                ["k", "1984"],
                ["authors", "$contacts"],
                ["tag", "p", "$contacts"]
            ]
        )!
        let spell = SpellEvent.parse(from: ev)

        XCTAssertNotNil(spell)
        XCTAssertEqual(spell?.authors, [.variable(.contacts)])
        XCTAssertEqual(spell?.tagFilters.count, 1)
        XCTAssertEqual(spell?.tagFilters.first?.letter, "p")
        XCTAssertEqual(spell?.tagFilters.first?.values, [.variable(.contacts)])
        XCTAssertTrue(spell?.requiresContacts ?? false)
    }

    // MARK: - Rejection cases

    func test_reject_missing_cmd() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["k", "1"]]
        )!
        let spell = SpellEvent.parse(from: ev)
        XCTAssertNil(spell, "Spell without cmd tag should be rejected")
    }

    func test_reject_no_filter_tags() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["name", "Empty"]]
        )!
        let spell = SpellEvent.parse(from: ev)
        XCTAssertNil(spell, "Spell without any filter tags should be rejected")
    }

    func test_reject_wrong_kind() {
        let ev = NostrEvent(
            content: "hello",
            keypair: test_keypair,
            kind: 1,
            tags: [["cmd", "REQ"], ["k", "1"]]
        )!
        let spell = SpellEvent.parse(from: ev)
        XCTAssertNil(spell, "Non-777 event should be rejected")
    }
}
