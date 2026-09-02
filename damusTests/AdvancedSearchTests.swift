//
//  AdvancedSearchTests.swift
//  damusTests
//
//  Created by William Casarin on 2026-09-01.
//

import XCTest
@testable import damus

// MARK: - The query model

final class AdvancedSearchQueryTests: XCTestCase {
    let author_a = Pubkey(hex: "32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8")!
    let author_b = Pubkey(hex: "51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3")!

    /// Duplicate pubkeys must not survive into a filter: nostrdb's author-kind
    /// merger opens one scanner per author*kind group and never deduplicates, so
    /// the same author twice returns every note twice.
    func test_authors_are_deduplicated_preserving_order() {
        var query = AdvancedSearchQuery(authors: [author_b, author_a, author_b])
        XCTAssertEqual(query.authors, [author_b, author_a])

        // and again on assignment, not just at init
        query.authors = [author_a, author_a, author_b, author_a]
        XCTAssertEqual(query.authors, [author_a, author_b])
    }

    func test_blank_terms_are_dropped() {
        var query = AdvancedSearchQuery(keywords: ["  art  ", "", "   "], phrases: ["\n"])
        XCTAssertEqual(query.keywords, ["art"])
        XCTAssertEqual(query.phrases, [])

        query.keywords = [" fox ", ""]
        XCTAssertEqual(query.keywords, ["fox"])
    }

    /// An author query with no kinds falls through to `NDB_PLAN_CREATED`, a full
    /// scan, so the model refuses to hold an empty kind set.
    func test_kinds_are_never_empty() {
        var query = AdvancedSearchQuery(kinds: [])
        XCTAssertEqual(query.kinds, AdvancedSearchQuery.defaultKinds)
        XCTAssertEqual(query.kinds, [.text, .longform])

        query.kinds = []
        XCTAssertEqual(query.kinds, AdvancedSearchQuery.defaultKinds)

        query.kinds = [.text]
        XCTAssertEqual(query.kinds, [.text])
    }

    func test_sorted_kinds_is_stable() {
        let query = AdvancedSearchQuery(kinds: [.longform, .text])
        XCTAssertEqual(query.sortedKinds, [.text, .longform])
    }

    /// `authors * kinds` must stay under `NDB_MAX_AUTHOR_KIND_SCANNERS` (64) or
    /// the query falls off the fast plan onto an unbounded post-filter scan.
    func test_author_limit_follows_the_kind_count() {
        XCTAssertEqual(AdvancedSearchQuery(kinds: [.text, .longform]).authorLimit, 32)
        XCTAssertEqual(AdvancedSearchQuery(kinds: [.text]).authorLimit, 64)

        let authors = (0..<33).map({ i in Pubkey(Data(repeating: UInt8(i), count: 32)) })
        XCTAssertFalse(AdvancedSearchQuery(authors: Array(authors.prefix(32))).exceedsAuthorLimit)
        XCTAssertTrue(AdvancedSearchQuery(authors: authors).exceedsAuthorLimit)
    }

    func test_empty_and_trivial() {
        XCTAssertTrue(AdvancedSearchQuery().isEmpty)
        XCTAssertTrue(AdvancedSearchQuery().isTrivial)

        // a date range on its own is not a search
        let dates_only = AdvancedSearchQuery(since: Date(timeIntervalSince1970: 1), until: Date(timeIntervalSince1970: 2))
        XCTAssertFalse(dates_only.isEmpty)
        XCTAssertTrue(dates_only.isTrivial)

        XCTAssertFalse(AdvancedSearchQuery(keywords: ["art"]).isTrivial)
        XCTAssertFalse(AdvancedSearchQuery(phrases: ["a b"]).isTrivial)
        XCTAssertFalse(AdvancedSearchQuery(authors: [author_a]).isTrivial)
    }

    /// Both bounds are inclusive, so a fractional date floors to the second it
    /// falls in at either end.
    func test_dates_convert_to_floored_nostr_timestamps() {
        let query = AdvancedSearchQuery(since: Date(timeIntervalSince1970: 1700000000.9),
                                        until: Date(timeIntervalSince1970: 1700000009.9))
        XCTAssertEqual(query.sinceTimestamp, 1700000000)
        XCTAssertEqual(query.untilTimestamp, 1700000009)

        XCTAssertNil(AdvancedSearchQuery().sinceTimestamp)
        XCTAssertNil(AdvancedSearchQuery().untilTimestamp)

        // out of range dates clamp rather than trap
        XCTAssertEqual(AdvancedSearchQuery.timestamp(from: Date(timeIntervalSince1970: -1)), 0)
        XCTAssertEqual(AdvancedSearchQuery.timestamp(from: Date(timeIntervalSince1970: 1e12)), UInt32.max)
    }

    func test_empty_date_window() {
        let at = { (t: Double) in Date(timeIntervalSince1970: t) }

        XCTAssertFalse(AdvancedSearchQuery(since: at(10), until: at(20)).hasEmptyDateWindow)
        // inclusive bounds, so a single second is a real window
        XCTAssertFalse(AdvancedSearchQuery(since: at(10), until: at(10)).hasEmptyDateWindow)
        XCTAssertTrue(AdvancedSearchQuery(since: at(20), until: at(10)).hasEmptyDateWindow)
        XCTAssertFalse(AdvancedSearchQuery(since: at(20)).hasEmptyDateWindow)
    }
}

// MARK: - Content matching

final class SearchContentMatcherTests: XCTestCase {
    private func matches(_ content: String, keywords: [String] = [], phrases: [String] = []) -> Bool {
        SearchContentMatcher(keywords: keywords, phrases: phrases).matches(content)
    }

    /// The rule the card asks for: keywords match at a word boundary. They may
    /// match a *prefix* of a word, which is what nostrdb's own index does, so both
    /// search strategies agree on what a keyword means.
    func test_keywords_match_at_a_word_boundary() {
        XCTAssertTrue(matches("the art of war", keywords: ["art"]))
        XCTAssertTrue(matches("a fine artist", keywords: ["art"]), "a keyword may match a word prefix")
        XCTAssertFalse(matches("just getting started", keywords: ["art"]), "'art' must not match inside 'start'")
        XCTAssertFalse(matches("cart before horse", keywords: ["art"]))
    }

    func test_keywords_are_an_and() {
        XCTAssertTrue(matches("a quick brown fox", keywords: ["quick", "fox"]))
        XCTAssertFalse(matches("a quick brown fox", keywords: ["quick", "badger"]))
    }

    func test_matching_is_case_and_diacritic_insensitive() {
        XCTAssertTrue(matches("Un CAFÉ au lait", keywords: ["cafe"]))
        XCTAssertTrue(matches("un cafe au lait", keywords: ["CAFÉ"]))
        XCTAssertTrue(matches("Un CAFÉ au lait", phrases: ["café au"]))
    }

    /// Phrases are substring matches until Phase 3 gives them real exact-phrase
    /// semantics, and unlike keywords they are not word-boundary aware.
    func test_phrases_are_substring_matches() {
        XCTAssertTrue(matches("a quick brown fox", phrases: ["quick brown"]))
        XCTAssertTrue(matches("a quick brown fox", phrases: ["uick brow"]))
        XCTAssertFalse(matches("a quick brown fox", phrases: ["brown quick"]))
    }

    func test_punctuation_and_emoji_are_word_separators() {
        XCTAssertTrue(matches("nostr,damus;search", keywords: ["damus"]))
        XCTAssertTrue(matches("hello🎉world", keywords: ["world"]))
    }

    func test_an_empty_matcher_accepts_everything() {
        let matcher = SearchContentMatcher(keywords: [], phrases: [])
        XCTAssertTrue(matcher.isEmpty)
        XCTAssertTrue(matcher.matches("anything at all"))
        XCTAssertTrue(matcher.matches(""))
    }
}

// MARK: - Planning

final class AdvancedSearchPlannerTests: XCTestCase {
    let author_a = Pubkey(hex: "32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8")!

    func test_a_pinned_author_takes_the_author_scoped_strategy() {
        let query = AdvancedSearchQuery(keywords: ["art"], authors: [author_a])

        guard case .authorScoped(let filter, let maxResults, let matcher) = AdvancedSearchPlanner.plan(for: query) else {
            return XCTFail("expected the author-scoped strategy")
        }

        XCTAssertEqual(filter.authors, [author_a])
        XCTAssertEqual(filter.kinds, [.text, .longform], "kinds must always be set, or the query falls to a full scan")
        XCTAssertNil(filter.search, "the author-scoped strategy must not route onto nostrdb's SEARCH plan")
        XCTAssertEqual(maxResults, AdvancedSearchPlanner.authorScopedCandidateLimit)
        XCTAssertEqual(matcher, SearchContentMatcher(keywords: ["art"], phrases: []))
    }

    /// "No keywords at all" is the author-scoped strategy with the content match
    /// skipped — the index walk is the whole answer.
    func test_an_author_with_no_terms_skips_content_matching() {
        let query = AdvancedSearchQuery(authors: [author_a], since: Date(timeIntervalSince1970: 1700000000))

        guard case .authorScoped(let filter, _, let matcher) = AdvancedSearchPlanner.plan(for: query) else {
            return XCTFail("expected the author-scoped strategy")
        }

        XCTAssertNil(matcher)
        XCTAssertEqual(filter.since, 1700000000)
    }

    func test_no_author_takes_the_global_strategy() {
        let query = AdvancedSearchQuery(keywords: ["quick"], phrases: ["brown fox"])

        guard case .global(let probe, let filter, let limit, let matcher) = AdvancedSearchPlanner.plan(for: query) else {
            return XCTFail("expected the global strategy")
        }

        XCTAssertEqual(probe, "quick brown fox")
        XCTAssertNil(filter.authors)
        XCTAssertEqual(filter.kinds, [.text, .longform])
        XCTAssertEqual(limit, Ndb.max_text_search_results)
        XCTAssertFalse(matcher.isEmpty, "the global strategy always verifies its hits")
    }

    func test_queries_with_nothing_to_run() {
        func reason(_ query: AdvancedSearchQuery) -> AdvancedSearchPlan.Reason? {
            guard case .nothingToRun(let reason) = AdvancedSearchPlanner.plan(for: query) else { return nil }
            return reason
        }

        XCTAssertEqual(reason(AdvancedSearchQuery()), .emptyQuery)
        XCTAssertEqual(reason(AdvancedSearchQuery(since: Date(timeIntervalSince1970: 1))), .unconstrained)
        XCTAssertEqual(reason(AdvancedSearchQuery(keywords: ["art"],
                                                  authors: [author_a],
                                                  since: Date(timeIntervalSince1970: 20),
                                                  until: Date(timeIntervalSince1970: 10))), .emptyDateWindow)
        // nostrdb cannot match a word under two bytes, so there is nothing to probe
        XCTAssertEqual(reason(AdvancedSearchQuery(keywords: ["a", "b"])), .noIndexableTerms)
        // ...but with an author to scope to there is no probe to build, so it runs
        XCTAssertNil(reason(AdvancedSearchQuery(keywords: ["a"], authors: [author_a])))
    }

    // MARK: probe construction

    func test_probe_drops_words_the_index_cannot_match() {
        XCTAssertEqual(AdvancedSearchPlanner.probe(for: AdvancedSearchQuery(keywords: ["a", "quick", "brown", "fox"])),
                       "quick brown fox",
                       "single-character words are rejected by ndb_prefix_matches and would zero the result set")
    }

    func test_probe_deduplicates_and_splits_phrases() {
        let query = AdvancedSearchQuery(keywords: ["Fox"], phrases: ["quick, brown fox!"])
        XCTAssertEqual(AdvancedSearchPlanner.probe(for: query), "Fox quick brown",
                       "a repeated word costs a slot of the eight and buys nothing")
    }

    /// nostrdb silently drops query words past its cap of eight, in parse order,
    /// and because matching is an AND that *widens* the results. Truncating here
    /// makes it explicit, and the content matcher narrows the results back.
    func test_probe_truncates_to_the_nostrdb_word_cap() {
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let probe = AdvancedSearchPlanner.probe(for: AdvancedSearchQuery(keywords: words))

        XCTAssertEqual(Ndb.max_text_search_words, 8)
        XCTAssertEqual(probe.split(separator: " ").count, 8)
        XCTAssertEqual(probe, "one two three four five six seven eight")
    }
}

// MARK: - End to end against a seeded nostrdb

final class AdvancedSearchEngineTests: XCTestCase {
    var db_dir: String = ""

    /// The two authors of `multi_author_wire_events`, each with eight notes of the
    /// form "author A note 0" at alternating timestamps: A's are at
    /// 1700000000 + 2n, B's at 1700000001 + 2n.
    let author_a = Pubkey(hex: "32b3256865a224450d5f8d09c271ad1520fae7d940000f09c9d44dd7595e1bb8")!
    let author_b = Pubkey(hex: "51778facb56343cfd08eb21041886c0db2d840596b6e32b7d3ea1ad95fb98ae3")!

    override func setUpWithError() throws {
        db_dir = try XCTUnwrap(test_ndb_dir(), "could not create temp directory")
    }

    /// Ingests `events` and hands back a freshly opened Ndb to search.
    private func seeded(with events: String) throws -> Ndb {
        do {
            let ndb = try XCTUnwrap(Ndb(path: db_dir))
            XCTAssertTrue(ndb.process_events(events))
        }
        return try XCTUnwrap(Ndb(path: db_dir))
    }

    private func contents(_ ndb: Ndb, _ keys: [NoteKey]) throws -> [String] {
        return try ndb.compact_map_notes(keys: keys, { _, note in note.content })
    }

    private func search(_ ndb: Ndb, _ query: AdvancedSearchQuery) throws -> [String] {
        return try contents(ndb, try AdvancedSearchEngine.search(query, in: ndb))
    }

    private func at(_ timestamp: Double) -> Date { Date(timeIntervalSince1970: timestamp) }

    /// The question the whole epic exists to answer: what did this person post
    /// containing this phrase, between these dates.
    func test_author_phrase_and_window_returns_exactly_the_expected_notes() throws {
        let ndb = try seeded(with: multi_author_wire_events)

        let query = AdvancedSearchQuery(keywords: ["author"],
                                        phrases: ["note 3"],
                                        authors: [author_a],
                                        since: at(1700000004),
                                        until: at(1700000007))

        XCTAssertEqual(try search(ndb, query), ["author A note 3"])
    }

    func test_author_scoped_search_without_terms_returns_the_window() throws {
        let ndb = try seeded(with: multi_author_wire_events)

        let query = AdvancedSearchQuery(authors: [author_a], since: at(1700000010), until: at(1700000013))
        XCTAssertEqual(try search(ndb, query), ["author A note 6", "author A note 5"])
    }

    func test_order_flips_the_results() throws {
        let ndb = try seeded(with: multi_author_wire_events)

        let newest = AdvancedSearchQuery(authors: [author_a], since: at(1700000010), order: .newest_first)
        XCTAssertEqual(try search(ndb, newest), ["author A note 7", "author A note 6", "author A note 5"])

        var oldest = newest
        oldest.order = .oldest_first
        XCTAssertEqual(try search(ndb, oldest), ["author A note 5", "author A note 6", "author A note 7"])
    }

    // MARK: date window boundaries

    /// `since` is inclusive on both nostrdb and NIP-01: a note stamped exactly at
    /// the bound is part of the window.
    func test_since_boundary_is_inclusive() throws {
        let ndb = try seeded(with: multi_author_wire_events)

        let query = AdvancedSearchQuery(authors: [author_a], since: at(1700000012))
        XCTAssertEqual(try search(ndb, query), ["author A note 7", "author A note 6"],
                       "the note stamped exactly at `since` must be included")

        let past_it = AdvancedSearchQuery(authors: [author_a], since: at(1700000013))
        XCTAssertEqual(try search(ndb, past_it), ["author A note 7"])
    }

    /// `until` is inclusive per NIP-01, and ``AdvancedSearchQuery`` is written
    /// against that reading rather than carrying a compensating offset.
    ///
    /// nostrdb does not honour it yet — its shared filter matcher rejects
    /// `created_at >= until` and its descending seek steps past an exact hit at the
    /// bound, so the boundary note is unreachable through every query plan. That is
    /// tracked as `headway:nostrdb/govern-embrace-piece`. When it lands,
    /// `XCTExpectFailure` here starts failing for the opposite reason and should be
    /// deleted, leaving the assertion as the real test.
    func test_until_boundary_is_inclusive() throws {
        let ndb = try seeded(with: multi_author_wire_events)

        // everything strictly inside the bound comes back today
        let inside = AdvancedSearchQuery(authors: [author_a], since: at(1700000010), until: at(1700000013))
        XCTAssertEqual(try search(ndb, inside), ["author A note 6", "author A note 5"])

        let on_the_bound = AdvancedSearchQuery(authors: [author_a], since: at(1700000010), until: at(1700000012))
        let results = (try? search(ndb, on_the_bound)) ?? []

        XCTExpectFailure("nostrdb treats `until` as exclusive; see headway:nostrdb/govern-embrace-piece") {
            XCTAssertEqual(results, ["author A note 6", "author A note 5"],
                           "the note stamped exactly at `until` must be included")
        }

        // what it actually does today, so the divergence is pinned rather than implied
        XCTAssertEqual(results, ["author A note 5"])
    }

    // MARK: multi-author

    /// nostrdb's index merger interleaves the per-author runs and yields strictly
    /// newest-first. The fixture ingests A's whole run before B's and alternates
    /// their timestamps, so a concatenating plan would come back grouped by author.
    func test_multi_author_results_interleave_newest_first() throws {
        let ndb = try seeded(with: multi_author_wire_events)

        let query = AdvancedSearchQuery(keywords: ["note"], authors: [author_a, author_b])
        let results = try search(ndb, query)

        XCTAssertEqual(results.count, 16)
        XCTAssertEqual(results, (0..<8).reversed().flatMap({ n in ["author B note \(n)", "author A note \(n)"] }),
                       "results must interleave across authors, not concatenate per author")
    }

    /// A pubkey listed twice must not double every row. nostrdb opens one scanner
    /// per author*kind group and never deduplicates, so the model has to.
    func test_a_duplicated_author_does_not_duplicate_rows() throws {
        let ndb = try seeded(with: multi_author_wire_events)

        let query = AdvancedSearchQuery(keywords: ["note"], authors: [author_a, author_a])
        XCTAssertEqual(query.authors, [author_a])

        let results = try search(ndb, query)
        XCTAssertEqual(results.count, 8)
        XCTAssertEqual(Set(results).count, 8, "no note may appear twice")
        XCTAssertEqual(results, try search(ndb, AdvancedSearchQuery(keywords: ["note"], authors: [author_a])))
    }

    // MARK: the global strategy

    /// The probe is a candidate generator, not the query. A word nostrdb's index
    /// cannot match is dropped from the probe and checked in-process instead, so it
    /// narrows the results as intended rather than zeroing them.
    func test_global_search_survives_a_word_the_index_cannot_match() throws {
        let ndb = try seeded(with: multi_author_wire_events)

        XCTAssertEqual(try ndb.text_search(query: "a note").count, 0,
                       "control: nostrdb cannot match the single-character word at all")

        let query = AdvancedSearchQuery(keywords: ["a", "note"])
        XCTAssertEqual(try search(ndb, query).count, 16)

        // and the short word is still a real constraint, not silently ignored
        let unmatchable = AdvancedSearchQuery(keywords: ["z", "note"])
        XCTAssertEqual(try search(ndb, unmatchable), [])
    }

    /// nostrdb takes only the first eight words of a query and drops the rest,
    /// which *widens* the results because matching is an AND. Verifying each hit
    /// in-process closes that hole.
    func test_global_search_does_not_widen_past_the_word_cap() throws {
        let ndb = try seeded(with: test_wire_events)
        let nine = ["quick", "brown", "fox", "jumped", "over", "the", "lazy", "dog", "cat"]

        XCTAssertEqual(try ndb.text_search(query: nine.joined(separator: " ")).count, 1,
                       "control: nostrdb drops the ninth word and matches on the first eight")

        XCTAssertEqual(try search(ndb, AdvancedSearchQuery(keywords: nine)), [],
                       "the dropped word must still narrow the results")
    }

    /// The window is applied by nostrdb rather than by the matcher, so the global
    /// strategy honours it too. Only `since` is exercised here — `until`'s
    /// divergence has its own test above.
    func test_global_search_respects_the_date_window() throws {
        let ndb = try seeded(with: multi_author_wire_events)

        let query = AdvancedSearchQuery(keywords: ["note"], since: at(1700000013))
        XCTAssertEqual(try search(ndb, query), ["author B note 7", "author A note 7", "author B note 6"])
    }
}
