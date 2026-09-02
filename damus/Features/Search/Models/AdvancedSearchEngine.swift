//
//  AdvancedSearchEngine.swift
//  damus
//
//  Created by William Casarin on 2026-09-01.
//

import Foundation

/// Runs an ``AdvancedSearchQuery`` against the local nostrdb.
///
/// Synchronous and blocking on purpose: this is the engine, not the runner.
/// Getting it off the main thread, debounced and cancellable is Phase 5, and
/// paging past the first batch of results is Phase 4.
enum AdvancedSearchEngine {
    /// Searches `ndb` for the notes matching `query`.
    ///
    /// - Returns: matching note keys in `query.order`, or an empty array when the
    ///   query had nothing to run. Call ``AdvancedSearchPlanner/plan(for:)``
    ///   yourself if you need to tell "found nothing" from "searched nothing" —
    ///   ``AdvancedSearchPlan/Reason`` says which.
    static func search(_ query: AdvancedSearchQuery, in ndb: Ndb) throws -> [NoteKey] {
        return try run(AdvancedSearchPlanner.plan(for: query), order: query.order, in: ndb)
    }

    /// Runs an already-made plan. Split out from ``search(_:in:)`` so a caller
    /// that inspected the plan does not have to re-plan to run it.
    static func run(_ plan: AdvancedSearchPlan, order: NdbSearchOrder, in ndb: Ndb) throws -> [NoteKey] {
        switch plan {
        case .nothingToRun:
            return []

        case .authorScoped(let filter, let maxResults, let contentMatcher):
            let candidates = try ndb.query(filters: [try NdbFilter(from: filter)], maxResults: maxResults)
            // `ndb_query` takes no order argument: every plan seeks its index at
            // `until` and walks backwards, so results arrive newest-first. Reversing
            // is exact whenever the walk finished inside `maxResults`, which is what
            // that limit is sized for; a query that hits the cap gets the oldest of
            // the newest `maxResults` rather than the true oldest.
            let ordered = order == .newest_first ? candidates : candidates.reversed()
            guard let contentMatcher else { return Array(ordered) }
            return try keep(Array(ordered), matching: contentMatcher, in: ndb)

        case .global(let probe, let filter, let limit, let contentMatcher):
            let hits = try ndb.text_search(query: probe,
                                           filter: try NdbFilter(from: filter),
                                           limit: limit,
                                           order: order)
            return try keep(hits.map(\.noteKey), matching: contentMatcher, in: ndb)
        }
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
