//
//  AdvancedSearchPlanner.swift
//  damus
//
//  Created by William Casarin on 2026-09-01.
//

import Foundation

/// What to run for an ``AdvancedSearchQuery``, or why there is nothing to run.
enum AdvancedSearchPlan: Equatable {
    /// Walk nostrdb's pubkey-kind index for the pinned authors under `filter`,
    /// taking up to `maxResults` candidates, then keep the ones `contentMatcher`
    /// accepts.
    ///
    /// `contentMatcher` is `nil` when the query has no terms at all, in which case
    /// the index walk *is* the answer and no note has to be opened.
    ///
    /// This is the path that answers the question the feature exists for — "what
    /// did this person post about X between these dates" — and it is exact,
    /// phrase-capable, and time-bounded by the index rather than by a scan.
    case authorScoped(filter: NostrFilter, maxResults: Int, contentMatcher: SearchContentMatcher?)

    /// Probe nostrdb's fulltext index with `probe` under `filter`, taking up to
    /// `limit` hits, then keep the ones `contentMatcher` accepts.
    ///
    /// `probe` is deliberately not the whole query: nostrdb takes at most
    /// ``Ndb/max_text_search_words`` words and cannot match a word shorter than
    /// ``AdvancedSearchPlanner/minIndexableWordLength``. It is a candidate
    /// generator, never narrower than the real query, and `contentMatcher` is what
    /// actually decides.
    case global(probe: String, filter: NostrFilter, limit: Int, contentMatcher: SearchContentMatcher)

    /// Nothing worth running, and why.
    ///
    /// The reason matters to the UI: "we searched and found nothing" and "we did
    /// not search" need different words, and a confident empty state over a query
    /// that was never run is worse than no answer at all.
    case nothingToRun(reason: Reason)

    enum Reason: Equatable {
        /// No terms, no authors, no dates.
        case emptyQuery
        /// Only a date range — nothing to search *for*, so running it would walk
        /// every note in the database.
        case unconstrained
        /// `since` falls after `until`, so no note can match.
        case emptyDateWindow
        /// A global search whose every word is too short for nostrdb's index,
        /// leaving nothing to probe with.
        case noIndexableTerms
    }
}

/// Picks how to answer an ``AdvancedSearchQuery`` against the local database.
///
/// Two strategies, chosen by whether an author is pinned. With authors we walk
/// the pubkey-kind index, which is bounded by the date window and returns exact,
/// unlimited results. Without them the fulltext index is the only way in, with
/// everything that implies: a 128-hit ceiling and a word-based probe.
enum AdvancedSearchPlanner {
    /// How many candidate rows the author-scoped strategy asks nostrdb for.
    ///
    /// Content matching happens *after* the index walk, so this bounds candidates
    /// rather than results: an author with ten thousand notes and one match still
    /// needs the walk to reach it. `struct ndb_query_result` is 24 bytes (a
    /// pointer and two `uint64_t`s), so the buffer is 4096 * 24 = 96 KB, heap
    /// allocated for the length of the query and freed with it. That is cheap
    /// enough to be generous with, and generous enough to cover a very prolific
    /// author in a single pass.
    ///
    /// Paging past it is Phase 4's job.
    static let authorScopedCandidateLimit = 4096

    /// The shortest word nostrdb's fulltext index can match, in UTF-8 bytes.
    ///
    /// `ndb_prefix_matches` (`nostrdb/src/nostrdb.c:6323`) rejects any search word
    /// shorter than two bytes outright — which is why a query containing "a"
    /// returns nothing at all rather than being ignored. Such words are dropped
    /// from the probe and left to ``SearchContentMatcher`` instead, so they narrow
    /// the results as the user intended rather than zeroing them.
    static let minIndexableWordLength = 2

    static func plan(for query: AdvancedSearchQuery) -> AdvancedSearchPlan {
        if query.isTrivial {
            return .nothingToRun(reason: query.isEmpty ? .emptyQuery : .unconstrained)
        }
        if query.hasEmptyDateWindow {
            return .nothingToRun(reason: .emptyDateWindow)
        }

        let matcher = SearchContentMatcher(query: query)

        guard query.authors.isEmpty else {
            return .authorScoped(filter: filter(for: query),
                                 maxResults: authorScopedCandidateLimit,
                                 contentMatcher: matcher.isEmpty ? nil : matcher)
        }

        // No author to scope to, so the fulltext index is the only way in.
        let probe = self.probe(for: query)
        guard !probe.isEmpty else { return .nothingToRun(reason: .noIndexableTerms) }

        return .global(probe: probe,
                       filter: filter(for: query),
                       limit: Ndb.max_text_search_results,
                       contentMatcher: matcher)
    }

    /// The nostrdb filter both strategies share.
    ///
    /// Note what is *not* here: no `search`. A filter carrying `NDB_FILTER_SEARCH`
    /// routes `ndb_query` onto its SEARCH plan, and the global strategy calls
    /// `Ndb.text_search` with this filter directly instead — same code underneath,
    /// but with the result limit and ordering under our control.
    static func filter(for query: AdvancedSearchQuery) -> NostrFilter {
        return NostrFilter(kinds: query.sortedKinds,
                           since: query.sinceTimestamp,
                           until: query.untilTimestamp,
                           authors: query.authors.isEmpty ? nil : query.authors)
    }

    /// The word list handed to nostrdb's fulltext index.
    ///
    /// Every keyword, then every word of every phrase, in that order: split on
    /// non-alphanumerics, words too short for the index dropped, duplicates
    /// dropped (they cost a slot and buy nothing), and the rest truncated to
    /// ``Ndb/max_text_search_words``.
    ///
    /// Truncating here is the point. nostrdb drops words past its cap silently and
    /// in parse order, and because matching is an AND that *widens* the result set
    /// rather than narrowing it — someone typing a long phrase quietly gets more
    /// than they asked for. Doing the truncation ourselves makes it visible, and
    /// running every hit through ``SearchContentMatcher`` afterwards narrows the
    /// results back to the query that was actually typed.
    ///
    /// Words keep the case the user typed them in: nostrdb lowercases both the
    /// index keys and the search words itself, but it does not fold diacritics, so
    /// folding here would stop "café" from matching an indexed "café".
    static func probe(for query: AdvancedSearchQuery) -> String {
        var seen = Set<String>()
        var words: [String] = []

        for term in query.keywords + query.phrases {
            for word in term.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                guard word.utf8.count >= minIndexableWordLength else { continue }
                guard seen.insert(SearchContentMatcher.folded(String(word))).inserted else { continue }

                words.append(String(word))
                if words.count == Ndb.max_text_search_words {
                    return words.joined(separator: " ")
                }
            }
        }

        return words.joined(separator: " ")
    }
}
