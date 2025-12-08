//
//  NIP05GroupedListView.swift
//  damus
//
//  Created by alltheseas on 2025-12-07.
//

import SwiftUI

// MARK: - Author Group Model

/// Represents an aggregated group of posts from a single author.
/// Used by the grouped view to show one row per author with their post count.
struct AuthorGroup: Identifiable {
    let pubkey: Pubkey
    let latestEvent: NostrEvent
    let postCount: Int

    var id: Pubkey { pubkey }
}

// MARK: - Filter Value Snapshot

/// Value-type snapshot of filter inputs for deterministic, testable grouping.
/// Decouples the grouping logic from the `ObservableObject` reference type.
struct GroupedFilterValues {
    let timeRangeSeconds: UInt32
    let includeReplies: Bool
    let hideShortNotes: Bool
    let filteredWords: String
    let maxNotesPerUser: Int?
}

extension NIP05FilterSettings {
    var filterValues: GroupedFilterValues {
        GroupedFilterValues(
            timeRangeSeconds: timeRange.seconds,
            includeReplies: includeReplies,
            hideShortNotes: hideShortNotes,
            filteredWords: filteredWords,
            maxNotesPerUser: maxNotesPerUser
        )
    }
}

// MARK: - Grouped Timeline Grouper

/// Pure-function grouping and filtering logic extracted from the view for testability.
/// All methods are static and take value-type inputs — no reference types or SwiftUI dependencies.
struct GroupedTimelineGrouper {

    /// Groups events by author, applying all filters, and returns sorted author groups.
    static func group(
        events: [NostrEvent],
        filter: (NostrEvent) -> Bool,
        values: GroupedFilterValues,
        now: Date = Date()
    ) -> [AuthorGroup] {
        let wordsList = parseFilteredWords(values.filteredWords)
        let cutoff = UInt32(now.timeIntervalSince1970) - values.timeRangeSeconds

        var groupsByAuthor: [Pubkey: (latest: NostrEvent, count: Int)] = [:]

        for event in events {
            guard shouldIncludeEvent(event, filter: filter, values: values, wordsList: wordsList, cutoff: cutoff) else { continue }

            if let existing = groupsByAuthor[event.pubkey] {
                let newLatest = event.created_at > existing.latest.created_at ? event : existing.latest
                groupsByAuthor[event.pubkey] = (latest: newLatest, count: existing.count + 1)
            } else {
                groupsByAuthor[event.pubkey] = (latest: event, count: 1)
            }
        }

        if let maxNotes = values.maxNotesPerUser {
            groupsByAuthor = groupsByAuthor.filter { $0.value.count <= maxNotes }
        }

        return groupsByAuthor
            .map { AuthorGroup(pubkey: $0.key, latestEvent: $0.value.latest, postCount: $0.value.count) }
            .sorted { $0.latestEvent.created_at > $1.latestEvent.created_at }
    }

    // MARK: - Internal Filtering

    static func parseFilteredWords(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.count >= 2 }
    }

    static func shouldIncludeEvent(
        _ event: NostrEvent,
        filter: (NostrEvent) -> Bool,
        values: GroupedFilterValues,
        wordsList: [String],
        cutoff: UInt32
    ) -> Bool {
        guard event.created_at >= cutoff else { return false }
        guard filter(event) else { return false }
        if !values.includeReplies && event.is_reply() { return false }
        if containsFilteredWords(event, wordsList: wordsList) { return false }
        if isTooShort(event, hideShortNotes: values.hideShortNotes) { return false }
        return true
    }

    static func containsFilteredWords(_ event: NostrEvent, wordsList: [String]) -> Bool {
        guard !wordsList.isEmpty else { return false }
        let content = event.content.lowercased()
        return wordsList.contains { content.contains($0) }
    }

    static func isTooShort(_ event: NostrEvent, hideShortNotes: Bool) -> Bool {
        guard hideShortNotes else { return false }

        let content = event.content.trimmingCharacters(in: .whitespacesAndNewlines)

        if content.count < 10 { return true }

        let textWithoutEmojis = content.unicodeScalars
            .filter { !$0.properties.isEmoji }
            .map { String($0) }
            .joined()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if textWithoutEmojis.count < 2 { return true }

        let words = content.split(whereSeparator: { $0.isWhitespace }).filter { !$0.isEmpty }
        if words.count == 1 { return true }

        return false
    }
}

// MARK: - Queue Manager

/// Manages EventHolder queue state for grouped mode transitions.
/// Extracted from View for testability.
struct GroupedModeQueueManager {
    /// Flushes queued events and disables queueing so grouped view sees all events.
    @MainActor
    static func flush(source: EventHolder) {
        source.flush()
        source.set_should_queue(false)
    }
}

// MARK: - Grouped List View

/// A list view that groups posts by author, showing one row per author.
/// Each row displays the author's profile, their most recent post preview, and total post count.
///
/// Supports filtering by:
/// - Reply exclusion
/// - Time range (24h, 7d)
/// - Keyword exclusion (comma-separated words)
/// - Short note filtering (fevela-style: <10 chars, emoji-only, single word)
/// - Max notes per user threshold
struct NIP05GroupedListView: View {
    let damus_state: DamusState
    let events: EventHolder
    let filter: (NostrEvent) -> Bool
    @ObservedObject var settings: NIP05FilterSettings

    /// Groups all events by author via the extracted pure-function grouper.
    var authorGroups: [AuthorGroup] {
        GroupedTimelineGrouper.group(
            events: events.all_events,
            filter: filter,
            values: settings.filterValues,
            now: Date()
        )
    }

    // MARK: - View Body

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(authorGroups) { group in
                Button {
                    damus_state.nav.push(route: Route.ProfileByKey(pubkey: group.pubkey))
                } label: {
                    NIP05GroupedAuthorRow(
                        damus_state: damus_state,
                        pubkey: group.pubkey,
                        latestEvent: group.latestEvent,
                        postCount: group.postCount
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 74)
            }

            if authorGroups.isEmpty {
                emptyStateView
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No matching posts")
                .font(.headline)
                .foregroundColor(.gray)

            if hasActiveFilters {
                Text("Try adjusting your filters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 40)
    }

    private var hasActiveFilters: Bool {
        let wordsList = GroupedTimelineGrouper.parseFilteredWords(settings.filteredWords)
        return !wordsList.isEmpty || settings.hideShortNotes || settings.maxNotesPerUser != nil
    }
}

// MARK: - Preview

#Preview {
    let damus_state = test_damus_state
    let holder = EventHolder(on_queue: { _ in })
    NIP05GroupedListView(
        damus_state: damus_state,
        events: holder,
        filter: { _ in true },
        settings: NIP05FilterSettings()
    )
}
