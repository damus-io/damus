//
//  NDBSearchView.swift
//  damus
//
//  Created by eric on 9/9/24.
//

import SwiftUI

struct NDBSearchView: View {
    let damus_state: DamusState
    @Binding var results: [NostrEvent]
    let searchQuery: String
    @Binding var is_loading: Bool
    @Binding var relay_result_count: Int
    @Binding var relay_search_attempted: Bool
    var onEnableRelaySearch: (() -> Void)? = nil

    /// Extracts search terms for highlighting in results.
    var highlightTerms: [String] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
        var terms: [String] = []

        for part in parts {
            let term = String(part)
            let strippedHashtag = term.hasPrefix("#") ? String(term.dropFirst()) : nil

            if let stripped = strippedHashtag, !stripped.isEmpty {
                terms.append(stripped)
            }

            if !term.isEmpty {
                terms.append(term)
            }
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for term in terms.map({ $0.lowercased() }) {
            if seen.insert(term).inserted {
                deduped.append(term)
            }
        }

        return deduped
    }

    /// Badge showing relay search status (NIP-50).
    var relayBadge: some View {
        Group {
            if relay_result_count > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.secondary)
                    Text("Relay results included")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if relay_search_attempted {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(.secondary)
                    Text("Relay search sent")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    var body: some View {
        ScrollView {
            if is_loading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                }
                .padding()
            }

            relayBadge

            if results.count > 0 {
                HStack {
                    Spacer()
                    Image("search")
                    Text("Top hits", comment: "A label indicating that the notes being displayed below it are all top note search results")
                    Spacer()
                }
                .padding()
                .foregroundColor(.secondary)

                if !highlightTerms.isEmpty {
                    Text("Search: \(searchQuery)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                LazyVStack {
                    ForEach(results, id: \.self) { note in
                        EventView(damus: damus_state, event: note, options: [.truncate_content], highlightTerms: highlightTerms)
                            .onTapGesture {
                                let event = note.get_inner_event(cache: damus_state.events) ?? note
                                let thread = ThreadModel(event: event, damus_state: damus_state)
                                damus_state.nav.push(route: Route.Thread(thread: thread))
                            }
                            .padding(.horizontal)

                        ThiccDivider()
                    }
                }

                // Show compact suggestion when results are sparse
                if shouldShowRelaySearchSuggestion(settings: damus_state.settings, resultCount: results.count) {
                    RelaySearchSuggestionView(
                        settings: damus_state.settings,
                        query: searchQuery,
                        isEmptyResults: false,
                        onEnable: {
                            damus_state.settings.enable_nip50_relay_search = true
                            onEnableRelaySearch?()
                        }
                    )
                    .padding(.top, 16)
                }

            } else if results.count == 0 {
                HStack {
                    Spacer()
                    Image("search")
                    Text("No results", comment: "A label indicating that note search resulted in no results")
                    Spacer()
                }
                .padding()
                .foregroundColor(.secondary)

                // Show prominent suggestion when no results
                if shouldShowRelaySearchSuggestion(settings: damus_state.settings, resultCount: 0) {
                    RelaySearchSuggestionView(
                        settings: damus_state.settings,
                        query: searchQuery,
                        isEmptyResults: true,
                        onEnable: {
                            damus_state.settings.enable_nip50_relay_search = true
                            onEnableRelaySearch?()
                        }
                    )
                    .padding(.top, 8)
                }
            }
        }
    }
}

// MARK: - Relay Search Suggestion

/// Determines whether to show the relay search suggestion.
///
/// - Parameters:
///   - settings: User settings store
///   - resultCount: Number of local search results
/// - Returns: True if suggestion should be shown
func shouldShowRelaySearchSuggestion(settings: UserSettingsStore, resultCount: Int) -> Bool {
    guard !settings.enable_nip50_relay_search else { return false }
    guard !settings.dismiss_relay_search_suggestion else { return false }
    return resultCount < 5
}

/// Contextual suggestion card prompting users to enable NIP-50 relay search.
///
/// Shows in search results when relay search is disabled, informing users
/// of the option and its privacy implications.
struct RelaySearchSuggestionView: View {
    let settings: UserSettingsStore
    let query: String
    let isEmptyResults: Bool
    let onEnable: () -> Void

    var body: some View {
        if isEmptyResults {
            emptyStateView
        } else {
            compactSuggestionCard
        }
    }

    /// Prominent view shown when local search returns no results.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Try searching on relays for \(query)?", comment: "Title suggesting user try relay search for their query")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Expand your search for \(query) to nostr relays. Relay operators may see your search terms.", comment: "Description of relay search with privacy note")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                onEnable()
            }) {
                Text("Search relays for \(query)", comment: "Button to enable relay search for query")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            Button(action: {
                settings.dismiss_relay_search_suggestion = true
            }) {
                Text("Don't show again", comment: "Button to permanently dismiss relay search suggestion")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    /// Subtle inline card shown when local search returns sparse results.
    private var compactSuggestionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Search relays for \(query)?", comment: "Compact suggestion to enable relay search for query")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Relay operators may see your search terms", comment: "Brief privacy note for relay search")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                onEnable()
            }) {
                Text("Enable", comment: "Button to enable relay search")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
        .overlay(alignment: .topTrailing) {
            Button(action: {
                settings.dismiss_relay_search_suggestion = true
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(8)
            }
            .padding(.trailing, 8)
        }
    }
}
