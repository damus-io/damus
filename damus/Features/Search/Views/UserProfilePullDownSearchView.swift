//
//  UserProfilePullDownSearchView.swift
//  damus
//
//  Created for user profile search feature (GitHub #414).
//  Adapts PullDownSearchView to search only within a specific user's notes.
//

import Foundation
import SwiftUI

/// A pull-down search view scoped to a specific user's notes.
///
/// This view provides iOS-native pull-down-to-search functionality
/// filtered to only show notes from the specified author pubkey.
/// Used in ProfileView to enable "search this user's notes".
struct UserProfilePullDownSearchView: View {
    // MARK: - Properties

    let state: DamusState
    let author: Pubkey
    let on_cancel: () -> Void

    /// Binding to communicate search active state to parent view.
    /// Parent uses this to hide profile content when search is active.
    @Binding var is_active: Bool

    // MARK: - State

    @State private var search_text = ""
    @State private var results: [NostrEvent] = []
    @State private var cached_placeholder: String = ""

    /// Debouncer prevents excessive searches while user is typing.
    /// 0.25s delay balances responsiveness with performance.
    private let debouncer = Debouncer(interval: 0.25)

    // MARK: - Search Logic

    /// Performs author-scoped text search and updates results.
    ///
    /// Uses the new `text_search_by_author` method in Ndb to efficiently
    /// find notes matching the query from this specific user.
    private func do_search(query: String) {
        // Don't search empty queries
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            Task { @MainActor in
                results = []
            }
            return
        }

        let limit = 64
        let note_keys = (try? state.ndb.text_search_by_author(
            query: query,
            author: author,
            limit: limit,
            order: .newest_first
        )) ?? []

        // No results found
        guard !note_keys.isEmpty else {
            Task { @MainActor in
                results = []
            }
            return
        }

        // Convert NoteKeys to NostrEvents
        var found_events: [NostrEvent] = []
        var seen_keys = Set<NoteKey>()

        for note_key in note_keys {
            // Skip duplicates
            guard !seen_keys.contains(note_key) else { continue }

            try? state.ndb.lookup_note_by_key(note_key) { maybe_note in
                switch maybe_note {
                case .none:
                    return
                case .some(let note):
                    found_events.append(note.toOwned())
                    seen_keys.insert(note_key)
                }
            }
        }

        // Update UI on main thread
        let events_to_display = found_events
        Task { @MainActor in
            results = events_to_display
        }
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            searchResults
        }
        .clipped()
        .onAppear {
            loadPlaceholder()
        }
    }

    /// The search input field styled to match native iOS search bar.
    private var searchBar: some View {
        HStack(spacing: 8) {
            // Native iOS-style search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(.placeholderText))
                    .font(.system(size: 17, weight: .regular))

                TextField(cached_placeholder, text: $search_text)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .onChange(of: search_text) { query in
                        debouncer.debounce {
                            Task.detached {
                                do_search(query: query)
                            }
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            is_active = true
                        }
                    }

                // Clear button (like native iOS)
                if !search_text.isEmpty {
                    Button(action: {
                        search_text = ""
                        results = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(.placeholderText))
                            .font(.system(size: 17))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            // Cancel button slides in from right
            if is_active {
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        search_text = ""
                        results = []
                        is_active = false
                        end_editing()
                        on_cancel()
                    }
                }) {
                    Text("Cancel", comment: "Button to cancel out of search text entry mode.")
                        .foregroundColor(.accentColor)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Loads the placeholder text asynchronously to avoid blocking the main thread.
    private func loadPlaceholder() {
        Task.detached { [state, author] in
            let profile = try? state.ndb.lookup_profile_and_copy(author)
            let name = Profile.displayName(profile: profile, pubkey: author).username
            let placeholder = String(
                format: NSLocalizedString("Search @%@'s notes", comment: "Placeholder for searching a specific user's notes. The variable is the username."),
                name
            )
            await MainActor.run {
                cached_placeholder = placeholder
            }
        }
    }

    /// Displays search results or appropriate empty state.
    @ViewBuilder
    private var searchResults: some View {
        if !results.isEmpty {
            resultsList
        } else if !search_text.isEmpty {
            noResultsView
        }
        // When search_text is empty, show nothing (profile content shows below)
    }

    private var resultsList: some View {
        ForEach(results, id: \.self) { note in
            EventView(damus: state, event: note, options: [.wide])
                .onTapGesture {
                    navigateToThread(for: note)
                }
        }
        .padding(.horizontal, Theme.safeAreaInsets?.left)
        .padding(.top, 8)
    }

    private var noResultsView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            Text("No results", comment: "A label indicating that note search resulted in no results")
            Spacer()
        }
        .padding(.horizontal)
        .foregroundColor(.secondary)
    }

    /// Navigates to the thread view for a tapped note.
    private func navigateToThread(for note: NostrEvent) {
        let event = note.get_inner_event(cache: state.events) ?? note
        let thread = ThreadModel(event: event, damus_state: state)
        state.nav.push(route: Route.Thread(thread: thread))
    }
}

// MARK: - Preview

struct UserProfilePullDownSearchView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        UserProfilePullDownSearchView(
            state: state,
            author: state.pubkey,
            on_cancel: {},
            is_active: .constant(false)
        )
    }
}
