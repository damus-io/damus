//
//  AdvancedSearchQuery.swift
//  damus
//
//  Created by William Casarin on 2026-09-01.
//

import Foundation

/// A fully specified local search over nostrdb: what to look for, whose notes to
/// look in, and when.
///
/// This is the headless input to ``AdvancedSearchPlanner``, which turns it into a
/// concrete nostrdb query, and to ``AdvancedSearchEngine``, which runs it. It
/// holds no view state and touches no database, so it is cheap to build, compare
/// and test.
///
/// The type keeps itself normalized on assignment: blank terms are dropped,
/// authors are deduplicated, and ``kinds`` is never empty. Those are not
/// cosmetic — each one is a constraint nostrdb's query planner imposes, and the
/// per-property notes say what goes wrong when it is violated.
struct AdvancedSearchQuery: Equatable {
    /// Words that must all appear in a note's content for it to match.
    ///
    /// Matching is an AND across keywords, and each one matches at a word
    /// boundary — see ``SearchContentMatcher`` for the exact rule.
    var keywords: [String] {
        didSet { keywords = Self.normalized(terms: keywords) }
    }

    /// Runs of text that must appear verbatim in a note's content.
    ///
    /// Today these are case- and diacritic-insensitive substring matches. Real
    /// exact-phrase semantics — whitespace normalization, boundary handling — are
    /// Phase 3's job; this field is the seam for it.
    var phrases: [String] {
        didSet { phrases = Self.normalized(terms: phrases) }
    }

    /// Hashtags (`t` tags) a note must carry, without the leading `#`.
    ///
    /// Lowercased on assignment, because that is the form nostrdb's tag index is
    /// keyed by for a hashtag written any which way — the same normalization
    /// ``NostrFilter/filter_hashtag(_:)`` already does for the rest of the app.
    ///
    /// Unlike the term fields this is an *index* axis rather than a content one:
    /// it goes into the nostrdb filter and is checked while the index is walked,
    /// so it narrows the query rather than the results. See
    /// ``AdvancedSearchPlanner`` for which plan each shape lands on — notably a
    /// single hashtag is the only count that gets nostrdb's tag index.
    var hashtags: [String] {
        didSet { hashtags = Self.normalized(hashtags: hashtags) }
    }

    /// The authors to search, or empty to search everything nostrdb holds.
    ///
    /// Deduplicated on assignment, and that is load-bearing rather than tidy:
    /// nostrdb's author-kind index merger opens one scanner per author*kind group
    /// and never deduplicates its output, so the same pubkey listed twice returns
    /// every one of that author's notes twice. Dedupe here, not in the view.
    var authors: [Pubkey] {
        didSet { authors = Self.normalized(authors: authors) }
    }

    /// The oldest `created_at` to accept, inclusive.
    var since: Date?

    /// The newest `created_at` to accept, **inclusive**, per NIP-01.
    ///
    /// - Warning: nostrdb does not currently honour that. Its shared filter
    ///   matcher rejects `created_at >= until` (`ndb_filter_matches_with`,
    ///   `nostrdb/src/nostrdb.c:1605`) and its descending seek steps past an exact
    ///   hit at the bound, so a note landing exactly on `until` is unreachable
    ///   through every query plan. That is tracked as a nostrdb bug
    ///   (`headway:nostrdb/govern-embrace-piece`) and this model is deliberately
    ///   written against the fixed, NIP-01 behaviour rather than carrying a
    ///   compensating offset that would have to be found and removed later.
    var until: Date?

    /// The note kinds to search. Never empty — assigning an empty set restores
    /// ``defaultKinds``.
    ///
    /// Always sending kinds is a performance requirement. `ndb_filter_plan` only
    /// reaches the fast `NDB_PLAN_AUTHOR_KINDS` path when the filter carries both
    /// kinds and authors; an author query with no kinds falls through to
    /// `NDB_PLAN_CREATED`, which scans the whole created_at index. Since kinds 1
    /// and 30023 are the only fulltext-indexed ones anyway, there is never a
    /// reason to leave this unset.
    var kinds: Set<NostrKind> {
        didSet { if kinds.isEmpty { kinds = Self.defaultKinds } }
    }

    /// Whether results come back newest-first or oldest-first.
    var order: NdbSearchOrder

    init(keywords: [String] = [],
         phrases: [String] = [],
         hashtags: [String] = [],
         authors: [Pubkey] = [],
         since: Date? = nil,
         until: Date? = nil,
         kinds: Set<NostrKind> = AdvancedSearchQuery.defaultKinds,
         order: NdbSearchOrder = .newest_first) {
        self.keywords = Self.normalized(terms: keywords)
        self.phrases = Self.normalized(terms: phrases)
        self.hashtags = Self.normalized(hashtags: hashtags)
        self.authors = Self.normalized(authors: authors)
        self.since = since
        self.until = until
        self.kinds = kinds.isEmpty ? Self.defaultKinds : kinds
        self.order = order
    }

    // MARK: - nostrdb limits

    /// The kinds nostrdb fulltext-indexes, and so the only ones worth searching:
    /// text notes, voice transcripts, and long-form posts.
    static let defaultKinds: Set<NostrKind> = [.text, .voice, .longform]

    /// nostrdb's `NDB_MAX_AUTHOR_KIND_SCANNERS` (`nostrdb/src/nostrdb.c:96`),
    /// mirrored here because it is a `#define` in the `.c` and so invisible to
    /// Swift.
    static let maxAuthorKindScanners = 64

    /// The largest author set that still gets nostrdb's fast author-kind plan.
    ///
    /// `ndb_filter_plan` routes to `NDB_PLAN_AUTHOR_KINDS` only while
    /// `authors * kinds <= NDB_MAX_AUTHOR_KIND_SCANNERS`, so at the two
    /// fulltext-indexed kinds this is 32 authors. Past it the query falls back to
    /// `NDB_PLAN_KINDS`, whose post-filter is an unbounded scan — measurably slow
    /// for a sparse author set.
    ///
    /// A single author is special-cased in nostrdb and always takes the fast plan.
    var authorLimit: Int {
        max(1, Self.maxAuthorKindScanners / max(kinds.count, 1))
    }

    /// True when ``authors`` is big enough to fall off nostrdb's fast plan.
    ///
    /// The author picker should refuse to add past ``authorLimit`` rather than let
    /// a query silently take the slow path.
    var exceedsAuthorLimit: Bool { authors.count > authorLimit }

    // MARK: - Shape

    /// True when nothing at all has been entered.
    var isEmpty: Bool {
        keywords.isEmpty && phrases.isEmpty && hashtags.isEmpty && authors.isEmpty
            && since == nil && until == nil
    }

    /// True when there is nothing worth running.
    ///
    /// A query with no terms and no authors is just a date range over every note
    /// in the database, which is a timeline rather than a search. This — not
    /// ``isEmpty`` — is the check a pane should use to decide whether to run
    /// anything; ``isEmpty`` only separates "nothing entered" from "entered, but
    /// not enough to search on".
    var isTrivial: Bool {
        keywords.isEmpty && phrases.isEmpty && hashtags.isEmpty && authors.isEmpty
    }

    /// True when the date window cannot contain anything.
    ///
    /// Both bounds are inclusive, so `since == until` is a valid one-second
    /// window and only `since > until` is empty.
    var hasEmptyDateWindow: Bool {
        guard let since = sinceTimestamp, let until = untilTimestamp else { return false }
        return since > until
    }

    /// ``kinds`` in a stable order, so two equal queries build identical filters.
    var sortedKinds: [NostrKind] { kinds.sorted(by: { $0.rawValue < $1.rawValue }) }

    // MARK: - Nostr timestamps

    /// ``since`` as a nostr timestamp.
    var sinceTimestamp: UInt32? { Self.timestamp(from: since) }

    /// ``until`` as a nostr timestamp.
    var untilTimestamp: UInt32? { Self.timestamp(from: until) }

    /// Converts a `Date` to a nostr `created_at`.
    ///
    /// Both bounds are inclusive, so the date is floored to the second containing
    /// it: a `since` of 12:00:00.7 admits notes stamped 12:00:00, and an `until`
    /// of 12:00:00.7 admits them too. Dates outside the representable range clamp
    /// rather than trap.
    static func timestamp(from date: Date?) -> UInt32? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince1970.rounded(.down)
        guard seconds.isFinite else { return nil }
        if seconds <= 0 { return 0 }
        if seconds >= Double(UInt32.max) { return UInt32.max }
        return UInt32(seconds)
    }

    // MARK: - Normalization

    private static func normalized(terms: [String]) -> [String] {
        terms
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
    }

    private static func normalized(hashtags: [String]) -> [String] {
        var seen = Set<String>()
        return hashtags
            .map({ tag in
                var tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                while tag.hasPrefix("#") { tag = String(tag.dropFirst()) }
                return tag.filter({ !$0.isWhitespace }).lowercased()
            })
            .filter({ !$0.isEmpty && seen.insert($0).inserted })
    }

    private static func normalized(authors: [Pubkey]) -> [Pubkey] {
        var seen = Set<Pubkey>()
        return authors.filter({ seen.insert($0).inserted })
    }
}
