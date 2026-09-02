//
//  MutingTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2024-05-06.
//
import Foundation

import XCTest
@testable import damus

final class MutingTests: XCTestCase {
    @MainActor
    func testWordMuting() async {
        // Setup some test data
        let test_note = NostrEvent(
            content: "Nostr is the super app. Because it’s actually an ecosystem of apps, all of which make each other better. People haven’t grasped that yet. They will when it’s more accessible and onboarding is more straightforward and intuitive.",
            keypair: jack_keypair,
            createdAt: UInt32(Date().timeIntervalSince1970 - 100)
        )!
        let spammy_keypair = generate_new_keypair().to_keypair()
        let spammy_test_note = NostrEvent(
            content: "Some spammy airdrop just arrived! Why stack sats when you can get scammed instead with some random coin? Call 1-800-GET-SCAMMED to claim your airdrop today!",
            keypair: spammy_keypair,
            createdAt: UInt32(Date().timeIntervalSince1970 - 100)
        )!
        
        let mute_item: MuteItem = .word("airdrop", nil)
        let existing_mutelist = await test_damus_state.mutelist_manager.event

        guard
            let full_keypair = test_damus_state.keypair.to_full(),
            let mutelist = create_or_update_mutelist(keypair: full_keypair, mprev: existing_mutelist, to_add: mute_item)
        else {
            return
        }

        await test_damus_state.mutelist_manager.set_mutelist(mutelist)
        await test_damus_state.nostrNetwork.postbox.send(mutelist)
        
        let spammy_note_muted = await test_damus_state.mutelist_manager.is_event_muted(spammy_test_note)
        XCTAssert(spammy_note_muted)
        let test_note_muted = await test_damus_state.mutelist_manager.is_event_muted(test_note)
        XCTAssertFalse(test_note_muted)
    }
}


/// Muted notes must not reach text search results.
///
/// The mute check is a `NDB_FILTER_CUSTOM` element on the search filter, so
/// nostrdb rejects a muted note during its index walk. These tests pin both halves
/// of that: the muted notes are gone, *and* they did not quietly eat result slots
/// on their way out.
final class MutedTextSearchTests: XCTestCase {
    var db_dir: String = ""

    /// The user doing the searching. Never the author of anything here — a user's
    /// own notes are never muted, which would mask the thing being tested.
    let reader = generate_new_keypair()
    let muted_author = generate_new_keypair()
    let visible_author = generate_new_keypair()

    override func setUpWithError() throws {
        db_dir = try XCTUnwrap(test_ndb_dir(), "could not create temp directory")
    }

    private func note(_ content: String, by keypair: FullKeypair, at created_at: UInt32) throws -> NostrEvent {
        return try XCTUnwrap(NostrEvent(content: content, keypair: keypair.to_keypair(), createdAt: created_at))
    }

    /// Ingests `notes` and hands back a freshly opened Ndb to search.
    ///
    /// Ingestion is asynchronous; closing the database is what forces the flush, so
    /// the search has to run against a second handle.
    private func seeded(with notes: [NostrEvent]) throws -> Ndb {
        do {
            let ndb = try XCTUnwrap(Ndb(path: db_dir))
            for note in notes {
                let json = try XCTUnwrap(encode_json(note))
                XCTAssertTrue(ndb.process_event("[\"EVENT\",\"s\",\(json)]"))
            }
        }
        return try XCTUnwrap(Ndb(path: db_dir))
    }

    private func rules(muting items: MuteItem...) -> MuteRules {
        var users: Set<MuteItem> = []
        var hashtags: Set<MuteItem> = []
        var threads: Set<MuteItem> = []
        var words: Set<MuteItem> = []

        for item in items {
            switch item {
            case .user: users.insert(item)
            case .hashtag: hashtags.insert(item)
            case .word: words.insert(item)
            case .thread: threads.insert(item)
            }
        }

        return MuteRules(user_keypair: reader.to_keypair(), users: users, hashtags: hashtags, threads: threads, words: words)
    }

    private func search(_ ndb: Ndb, _ query: String, muting rules: MuteRules, limit: Int = Ndb.max_text_search_results) throws -> [String] {
        let hits = try ndb.text_search(query: query, filter: try NdbFilter.excluding(rules), limit: limit, order: .newest_first)
        return try ndb.compact_map_notes(keys: hits.map(\.noteKey), { _, note in note.content })
    }

    /// The bug: a muted author's notes came back from `ndb.text_search` like anyone
    /// else's, because the search path never consulted the mute list.
    func test_muted_author_is_dropped_from_text_search() throws {
        let ndb = try seeded(with: [
            try note("the ostrich sings at dawn", by: visible_author, at: 1700000000),
            try note("the ostrich hates dawn", by: muted_author, at: 1700000001),
        ])

        XCTAssertEqual(try search(ndb, "ostrich", muting: rules()),
                       ["the ostrich hates dawn", "the ostrich sings at dawn"],
                       "control: with nothing muted, both notes match")

        XCTAssertEqual(try search(ndb, "ostrich", muting: rules(muting: .user(muted_author.pubkey, nil))),
                       ["the ostrich sings at dawn"])
    }

    /// Why the check has to happen inside the query rather than over its output: a
    /// muted note must not take up one of the `limit` result slots on its way out.
    ///
    /// The muted author owns the two newest matches, so filtering the results of a
    /// `limit: 1` search would leave nothing at all.
    func test_a_muted_note_does_not_consume_a_result_slot() throws {
        let ndb = try seeded(with: [
            try note("an ostrich, older and unmuted", by: visible_author, at: 1700000000),
            try note("an ostrich, newer and muted", by: muted_author, at: 1700000001),
            try note("an ostrich, newest and muted", by: muted_author, at: 1700000002),
        ])

        XCTAssertEqual(try search(ndb, "ostrich", muting: rules(), limit: 1),
                       ["an ostrich, newest and muted"],
                       "control: the newest match is one the mute list will reject")

        XCTAssertEqual(try search(ndb, "ostrich", muting: rules(muting: .user(muted_author.pubkey, nil)), limit: 1),
                       ["an ostrich, older and unmuted"],
                       "the muted notes must be skipped, not counted and then dropped")
    }

    /// Search agrees with the timelines on what "muted" means, so the non-pubkey
    /// rules go through the same path. A muted word is enough to prove it.
    func test_muted_word_is_dropped_from_text_search() throws {
        let ndb = try seeded(with: [
            try note("the ostrich sings at dawn", by: visible_author, at: 1700000000),
            try note("the ostrich wants your airdrop", by: visible_author, at: 1700000001),
        ])

        XCTAssertEqual(try search(ndb, "ostrich", muting: rules(muting: .word("airdrop", nil))),
                       ["the ostrich sings at dawn"])
    }
}
