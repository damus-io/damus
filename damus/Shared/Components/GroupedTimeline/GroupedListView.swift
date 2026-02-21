//
//  GroupedListView.swift
//  damus
//
//  Created by alltheseas on 2025-12-07.
//

import SwiftUI

/// A list view that groups posts by author, showing one row per author.
/// Each row displays the author's profile, their most recent post preview, and total post count.
///
/// Supports filtering by:
/// - Reply exclusion
/// - Time range (24h, 7d)
/// - Keyword exclusion (comma-separated words)
/// - Short note filtering (fevela-style: <10 chars, emoji-only, single word)
/// - Max notes per user threshold
struct GroupedListView: View {
    let damus_state: DamusState
    @ObservedObject var events: EventHolder
    let filter: (NostrEvent) -> Bool
    @ObservedObject var settings: GroupedFilterSettings
    /// Called when the user taps an author row to visit their profile.
    var onProfileTapped: ((Pubkey) -> Void)? = nil

    // MARK: - View Body

    var body: some View {
        let groups = GroupedTimelineGrouper.group(
            events: events.all_events,
            filter: filter,
            values: settings.filterValues,
            now: Date()
        )

        LazyVStack(spacing: 0) {
            ForEach(groups) { group in
                Button {
                    onProfileTapped?(group.pubkey)
                    damus_state.nav.push(route: Route.ProfileByKey(pubkey: group.pubkey))
                } label: {
                    GroupedAuthorRow(
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

            if groups.isEmpty {
                emptyStateView
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No matching posts", comment: "Empty state title when no posts match the current filters")
                .font(.headline)
                .foregroundColor(.gray)

            if hasActiveFilters {
                Text("Try adjusting your filters", comment: "Empty state hint suggesting the user change filter settings")
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
    GroupedListView(
        damus_state: damus_state,
        events: holder,
        filter: { _ in true },
        settings: GroupedFilterSettings()
    )
}
