//
//  AdvancedSearchEngine.swift
//  damus
//
//  Created by William Casarin on 2026-09-01.
//

import Foundation

/// What one run of ``AdvancedSearchEngine`` found.
struct AdvancedSearchResults: Equatable {
    /// Matching note keys, in the order the query asked for.
    var keys: [NoteKey]

    /// True when nostrdb filled every result slot it was given, so there are
    /// probably more matches older than the last one here.
    ///
    /// This is measured on what *nostrdb* returned, before content matching, so it
    /// stays true even when the matcher then rejected most of them — which is
    /// exactly the case where a caller must not tell the user it found everything.
    /// Fetching the rest is Phase 4.
    var reachedLimit: Bool

    static let none = AdvancedSearchResults(keys: [], reachedLimit: false)
}

/// Runs an ``AdvancedSearchQuery`` against the local nostrdb.
///
/// Synchronous and blocking on purpose: this is the engine, not the runner.
/// Getting it off the main thread, debounced and cancellable is
/// ``AdvancedSearchModel``'s job, and paging past ``AdvancedSearchResults/reachedLimit``
/// is Phase 4.
enum AdvancedSearchEngine {
    /// Searches `ndb` for the notes matching `query`.
    ///
    /// - Parameters:
    ///   - query: What to look for.
    ///   - ndb: The database to look in.
    ///   - rules: Mute rules to reject notes by, or `nil` to search everything.
    ///     Handed to nostrdb as a filter predicate rather than applied to the
    ///     results, so a muted note never takes up one of the result slots — see
    ///     ``run(_:order:in:excluding:)``.
    /// - Returns: the matches, or ``AdvancedSearchResults/none`` when the query had
    ///   nothing to run. Call ``AdvancedSearchPlanner/plan(for:)`` yourself if you
    ///   need to tell "found nothing" from "searched nothing" —
    ///   ``AdvancedSearchPlan/Reason`` says which.
    static func search(_ query: AdvancedSearchQuery,
                       in ndb: Ndb,
                       excluding rules: MuteRules? = nil) throws -> AdvancedSearchResults {
        return try run(AdvancedSearchPlanner.plan(for: query),
                       order: query.order,
                       in: ndb,
                       excluding: rules)
    }

    /// Runs an already-made plan. Split out from ``search(_:in:excluding:)`` so a
    /// caller that inspected the plan does not have to re-plan to run it.
    static func run(_ plan: AdvancedSearchPlan,
                    order: NdbSearchOrder,
                    in ndb: Ndb,
                    excluding rules: MuteRules? = nil) throws -> AdvancedSearchResults {
        switch plan {
        case .nothingToRun:
            return .none

        case .indexWalk(let filter, let maxResults, let contentMatcher):
            let candidates = try ndb.query(filters: [try ndbFilter(filter, excluding: rules)],
                                           maxResults: maxResults)
            // `ndb_query` takes no order argument: every plan seeks its index at
            // `until` and walks backwards, so results arrive newest-first. Reversing
            // is exact whenever the walk finished inside `maxResults`, which is what
            // that limit is sized for; a query that hits the cap gets the oldest of
            // the newest `maxResults` rather than the true oldest.
            let ordered = order == .newest_first ? Array(candidates) : candidates.reversed()
            let keys = try contentMatcher.map({ try keep(Array(ordered), matching: $0, in: ndb) })
                ?? Array(ordered)
            return AdvancedSearchResults(keys: keys, reachedLimit: candidates.count >= maxResults)

        case .global(let probe, let filter, let limit, let contentMatcher):
            let hits = try ndb.text_search(query: probe,
                                           filter: try ndbFilter(filter, excluding: rules),
                                           limit: limit,
                                           order: order)
            return AdvancedSearchResults(keys: try keep(hits.map(\.noteKey), matching: contentMatcher, in: ndb),
                                         reachedLimit: hits.count >= limit)
        }
    }

    /// Converts a plan's filter, folding the mute rules in as a filter predicate.
    ///
    /// Muting is a filter axis rather than a post-pass because nostrdb checks a
    /// custom filter element wherever it checks the rest of the filter — inside the
    /// index walk, before a candidate takes up a result slot. Dropping muted notes
    /// from the results afterwards would instead quietly shrink them, which on the
    /// 128-capped global strategy means a heavily-muted search returning almost
    /// nothing while claiming it looked at everything.
    private static func ndbFilter(_ filter: NostrFilter, excluding rules: MuteRules?) throws -> NdbFilter {
        guard let rules else { return try NdbFilter(from: filter) }
        // The note handed to this closure is borrowed for the call and sized zero,
        // so it must not escape and must not be copied. `is_event_muted` only reads
        // it, which is what makes this safe.
        return try NdbFilter(from: filter, matching: { !rules.is_event_muted($0) })
    }

    /// Drops the candidates whose content `matcher` rejects.
    ///
    /// Notes that went missing between the index walk and the lookup are dropped
    /// too — nostrdb can hand back a key for a note that has since been evicted.
    private static func keep(_ keys: [NoteKey], matching matcher: SearchContentMatcher, in ndb: Ndb) throws -> [NoteKey] {
        return try ndb.compact_map_notes(keys: keys, { key, note in
            matcher.matches(note.content) ? key : nil
        })
    }
}
