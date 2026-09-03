//
//  NdbFilterTests.swift
//  damusTests
//
//  Covers `NdbFilterBuilder`, the wrapper around nostrdb's imperative
//  init/start-field/add-element/end-field/end sequence. The happy paths are
//  checked against `ndb_filter_matches` — the same matcher a query runs — rather
//  than by inspecting the struct, so a filter that builds without error but does
//  not actually match what it claims to still fails the test.
//

import XCTest
@testable import damus

final class NdbFilterTests: XCTestCase {
    let alice = generate_new_keypair()
    let bob = generate_new_keypair()

    /// Some timestamp on a day that means nothing in particular.
    static let timestamp: UInt32 = 1700000000

    // MARK: - Fixtures

    /// Builds a filter with `build`, hands it to `body`, and destroys it after.
    ///
    /// The slot is heap memory the test owns, which is the same shape
    /// ``NdbFilterArray`` uses: `NdbFilterBuilder` never allocates.
    private func withFilter(builtBy build: (NdbFilterBuilder) throws -> Void,
                            _ body: (UnsafeMutablePointer<ndb_filter>) throws -> Void) throws {
        let slot = UnsafeMutablePointer<ndb_filter>.allocate(capacity: 1)
        defer { slot.deallocate() }

        try NdbFilterBuilder.build(into: slot, build)
        defer { ndb_filter_destroy(slot) }

        try body(slot)
    }

    private func note(_ content: String,
                      _ keypair: FullKeypair,
                      kind: UInt32 = 1,
                      tags: [[String]] = [],
                      at timestamp: UInt32 = NdbFilterTests.timestamp) throws -> NostrEvent {
        return try XCTUnwrap(NostrEvent(content: content,
                                        keypair: keypair.to_keypair(),
                                        kind: kind,
                                        tags: tags,
                                        createdAt: timestamp))
    }

    /// Whether the filter matches the note, through nostrdb's own matcher.
    private func matches(_ filter: UnsafeMutablePointer<ndb_filter>, _ note: NostrEvent) -> Bool {
        return ndb_filter_matches(filter, note.note.ptr) == 1
    }

    // MARK: - Fields that build and match

    func test_a_since_field_matches_notes_at_or_after_the_cutoff() throws {
        let cutoff = Self.timestamp

        try withFilter(builtBy: { filter in
            try filter.field(.since, { try $0.add(int: UInt64(cutoff)) })
        }, { filter in
            XCTAssertTrue(matches(filter, try note("at the cutoff", alice, at: cutoff)),
                          "nostrdb's since is created_at >= since, so the cutoff itself is kept")
            XCTAssertTrue(matches(filter, try note("after", alice, at: cutoff + 1)))
            XCTAssertFalse(matches(filter, try note("before", alice, at: cutoff - 1)))
        })
    }

    func test_an_authors_field_matches_only_the_authors_added_to_it() throws {
        try withFilter(builtBy: { filter in
            try filter.field(.authors, { try $0.add(id: alice.pubkey) })
        }, { filter in
            XCTAssertTrue(matches(filter, try note("alice", alice)))
            XCTAssertFalse(matches(filter, try note("bob", bob)))
        })
    }

    func test_a_field_takes_more_than_one_element() throws {
        try withFilter(builtBy: { filter in
            try filter.field(.authors, { field in
                for pubkey in [alice.pubkey, bob.pubkey] {
                    try field.add(id: pubkey)
                }
            })
        }, { filter in
            XCTAssertTrue(matches(filter, try note("alice", alice)))
            XCTAssertTrue(matches(filter, try note("bob", bob)))
        })
    }

    func test_separate_fields_all_have_to_match() throws {
        // Fields are ANDed within one filter — it is whole filters that union.
        try withFilter(builtBy: { filter in
            try filter.field(.authors, { try $0.add(id: alice.pubkey) })
            try filter.field(.kinds, { try $0.add(int: 1) })
        }, { filter in
            XCTAssertTrue(matches(filter, try note("alice's kind 1", alice, kind: 1)))
            XCTAssertFalse(matches(filter, try note("alice's kind 0", alice, kind: 0)),
                           "the kinds field should reject a note the authors field accepts")
            XCTAssertFalse(matches(filter, try note("bob's kind 1", bob, kind: 1)))
        })
    }

    func test_a_tag_field_matches_a_referenced_pubkey() throws {
        try withFilter(builtBy: { filter in
            try filter.tagField("p", { try $0.add(id: bob.pubkey) })
        }, { filter in
            XCTAssertTrue(matches(filter, try note("mentions bob", alice, tags: [["p", bob.pubkey.hex()]])))
            XCTAssertFalse(matches(filter, try note("mentions nobody", alice)))
            XCTAssertFalse(matches(filter, try note("mentions alice", alice, tags: [["p", alice.pubkey.hex()]])))
        })
    }

    func test_a_tag_field_matches_a_string_element() throws {
        try withFilter(builtBy: { filter in
            try filter.tagField("t", { try $0.add(string: "damus") })
        }, { filter in
            XCTAssertTrue(matches(filter, try note("hashtagged", alice, tags: [["t", "damus"]])))
            XCTAssertFalse(matches(filter, try note("other hashtag", alice, tags: [["t", "nostr"]])))
        })
    }

    // MARK: - Failures leave nothing behind

    func test_an_element_of_the_wrong_type_is_rejected() throws {
        // nostrdb only allows strings in generic tags and search queries.
        XCTAssertThrowsError(try withFilter(builtBy: { filter in
            try filter.field(.authors, { try $0.add(string: "not an id") })
        }, { _ in })) { error in
            guard case NdbFilterBuildError.elementRejected = error else {
                return XCTFail("expected NdbFilterBuildError.elementRejected, got \(error)")
            }
        }
    }

    func test_a_second_value_in_a_single_valued_field_is_rejected() throws {
        XCTAssertThrowsError(try withFilter(builtBy: { filter in
            try filter.field(.since, { field in
                try field.add(int: 1)
                try field.add(int: 2)
            })
        }, { _ in })) { error in
            guard case NdbFilterBuildError.elementRejected = error else {
                return XCTFail("expected NdbFilterBuildError.elementRejected, got \(error)")
            }
        }
    }

    func test_an_id_that_is_not_32_bytes_is_refused_before_it_reaches_nostrdb() throws {
        // nostrdb reads 32 bytes from the pointer with no length to check, so this
        // has to be caught on our side or it reads past the end of the buffer.
        let short = Pubkey(Data(repeating: 0, count: 31))

        XCTAssertThrowsError(try withFilter(builtBy: { filter in
            try filter.field(.authors, { try $0.add(id: short) })
        }, { _ in })) { error in
            guard case NdbFilterBuildError.invalidIdLength(let bytes) = error else {
                return XCTFail("expected NdbFilterBuildError.invalidIdLength, got \(error)")
            }
            XCTAssertEqual(bytes, 31)
        }
    }

    func test_a_tag_outside_ascii_is_refused() throws {
        XCTAssertThrowsError(try withFilter(builtBy: { filter in
            try filter.tagField("é", { try $0.add(string: "x") })
        }, { _ in })) { error in
            guard case NdbFilterBuildError.tagNotASCII = error else {
                return XCTFail("expected NdbFilterBuildError.tagNotASCII, got \(error)")
            }
        }
    }

    func test_an_error_thrown_by_the_body_comes_back_out_unchanged() throws {
        struct Sentinel: Error {}

        XCTAssertThrowsError(try withFilter(builtBy: { filter in
            try filter.field(.authors, { _ in throw Sentinel() })
        }, { _ in })) { error in
            XCTAssertTrue(error is Sentinel, "the builder should not swallow or rewrap the caller's error, got \(error)")
        }
    }

    func test_a_slot_a_failed_build_touched_can_be_built_into_again() throws {
        // The contract that makes a throw safe: a failed build destroys what it
        // started, so the slot is free memory again rather than a half-filter that
        // would be double-destroyed or leaked.
        let slot = UnsafeMutablePointer<ndb_filter>.allocate(capacity: 1)
        defer { slot.deallocate() }

        XCTAssertThrowsError(try NdbFilterBuilder.build(into: slot, { filter in
            try filter.field(.since, { field in
                try field.add(int: 1)
                try field.add(int: 2)
            })
        }))

        try NdbFilterBuilder.build(into: slot, { filter in
            try filter.field(.authors, { try $0.add(id: alice.pubkey) })
        })
        defer { ndb_filter_destroy(slot) }

        XCTAssertTrue(matches(slot, try note("alice", alice)),
                      "the rebuilt filter should work exactly as if the failed build had never happened")
    }
}
