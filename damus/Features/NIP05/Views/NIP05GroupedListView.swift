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

// MARK: - Grouped List View

/// A list view that groups NIP-05 domain posts by author, showing one row per author.
/// Each row displays the author's profile, their most recent post preview, and total post count.
///
/// Supports filtering by:
/// - Time range (24h, 7d)
/// - Keyword exclusion (comma-separated words)
/// - Short note filtering (fevela-style: <10 chars, emoji-only, single word)
/// - Max notes per user threshold
struct NIP05GroupedListView: View {
    let damus_state: DamusState
    let events: EventHolder
    let filter: (NostrEvent) -> Bool
    @ObservedObject var settings: NIP05FilterSettings

    // MARK: - Filter Word Parsing

    /// Parses the comma-separated filter words from settings.
    /// Words must be at least 2 characters to avoid overly broad matches (e.g., "a" matching everything).
    private var filteredWordsList: [String] {
        settings.filteredWords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.count >= 2 }
    }

    // MARK: - Event Filtering

    /// Returns true if the event content contains any of the filtered words.
    /// Comparison is case-insensitive.
    private func containsFilteredWords(_ event: NostrEvent) -> Bool {
        guard !filteredWordsList.isEmpty else { return false }

        let content = event.content.lowercased()
        return filteredWordsList.contains { content.contains($0) }
    }

    /// Returns true if the event should be hidden for being "too short".
    /// Implements fevela-style filtering:
    /// - Less than 10 characters
    /// - Emoji-only (fewer than 2 non-emoji characters)
    /// - Single word only
    private func isTooShort(_ event: NostrEvent) -> Bool {
        guard settings.hideShortNotes else { return false }

        let content = event.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Too short: fewer than 10 characters total
        if content.count < 10 { return true }

        // Emoji-only: strip emojis and check for substantial text
        let textWithoutEmojis = content.unicodeScalars
            .filter { !$0.properties.isEmoji }
            .map { String($0) }
            .joined()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if textWithoutEmojis.count < 2 { return true }

        // Single word: no meaningful content
        let words = content.split(whereSeparator: { $0.isWhitespace }).filter { !$0.isEmpty }
        if words.count == 1 { return true }

        return false
    }

    /// Returns true if the event falls within the selected time range.
    private func isWithinTimeRange(_ event: NostrEvent) -> Bool {
        let cutoff = UInt32(Date.now.timeIntervalSince1970) - settings.timeRange.seconds
        return event.created_at >= cutoff
    }

    /// Returns true if the event passes all filters and should be included.
    private func shouldIncludeEvent(_ event: NostrEvent) -> Bool {
        // Time range check
        guard isWithinTimeRange(event) else { return false }

        // Content filter (mutes, etc.)
        guard filter(event) else { return false }

        // Keyword exclusion filter
        if containsFilteredWords(event) { return false }

        // Short note filter
        if isTooShort(event) { return false }

        return true
    }

    // MARK: - Author Grouping

    /// Groups all events by author, applying filters and tracking the latest event per author.
    var authorGroups: [AuthorGroup] {
        var groupsByAuthor: [Pubkey: (latest: NostrEvent, count: Int)] = [:]

        for event in events.all_events {
            guard shouldIncludeEvent(event) else { continue }

            if let existing = groupsByAuthor[event.pubkey] {
                // Update count; keep the more recent event as "latest"
                let newLatest = event.created_at > existing.latest.created_at ? event : existing.latest
                groupsByAuthor[event.pubkey] = (latest: newLatest, count: existing.count + 1)
            } else {
                groupsByAuthor[event.pubkey] = (latest: event, count: 1)
            }
        }

        // Apply max notes per user filter (exclude prolific posters)
        if let maxNotes = settings.maxNotesPerUser {
            groupsByAuthor = groupsByAuthor.filter { $0.value.count <= maxNotes }
        }

        // Convert to array sorted by most recent activity
        return groupsByAuthor
            .map { AuthorGroup(pubkey: $0.key, latestEvent: $0.value.latest, postCount: $0.value.count) }
            .sorted { $0.latestEvent.created_at > $1.latestEvent.created_at }
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
                    .padding(.leading, 74) // Align with text content, after profile pic
            }

            // Empty state with helpful message when filters exclude everything
            if authorGroups.isEmpty {
                emptyStateView
            }
        }
    }

    /// Empty state view shown when no posts match the current filters.
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No matching posts")
                .font(.headline)
                .foregroundColor(.gray)

            // Show filter hint only when filters are actively applied
            if hasActiveFilters {
                Text("Try adjusting your filters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 40)
    }

    /// Returns true if any user-configurable filters are currently active.
    private var hasActiveFilters: Bool {
        !filteredWordsList.isEmpty || settings.hideShortNotes || settings.maxNotesPerUser != nil
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
