//
//  SpellFeedView.swift
//  damus
//
//  Displays a spell feed with loading, empty, and error states.
//

import SwiftUI

struct SpellFeedView: View {
    let damus_state: DamusState
    @ObservedObject var model: SpellFeedModel

    var body: some View {
        switch model.state {
        case .idle:
            EmptyTimelineView()
                .onAppear {
                    model.subscribe()
                }

        case .loading:
            SpellFeedLoadingView()

        case .loaded:
            if model.events.isEmpty {
                SpellFeedEmptyView(spellName: model.spell.displayName)
            } else {
                ScrollView {
                    SpellTimelineView(
                        events: model.events,
                        damus: damus_state
                    )
                }
            }

        case .error(let error):
            SpellFeedErrorView(error: error, spellName: model.spell.displayName) {
                model.subscribe()
            }
        }
    }
}

// MARK: - State Views

struct SpellFeedLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading feed...", comment: "Loading indicator for a spell feed")
                .foregroundColor(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SpellFeedEmptyView: View {
    let spellName: String

    var body: some View {
        VStack(spacing: 12) {
            Image("question")
                .font(.system(size: 35))
                .padding()
            Text("No results for \"\(spellName)\"", comment: "Empty state for a spell feed with no matching events")
                .multilineTextAlignment(.center)
                .font(.callout.weight(.medium))
            Text("Try adjusting the feed or check back later.", comment: "Suggestion shown when a spell feed has no results")
                .multilineTextAlignment(.center)
                .font(.caption)
        }
        .foregroundColor(.gray)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SpellFeedErrorView: View {
    let error: SpellFeedError
    let spellName: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 35))
                .foregroundColor(.orange)

            Text(errorMessage)
                .multilineTextAlignment(.center)
                .font(.callout.weight(.medium))
                .foregroundColor(.primary)

            Button(action: onRetry) {
                Text("Retry", comment: "Button to retry loading a spell feed")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorMessage: String {
        switch error {
        case .resolutionFailed(let resError):
            switch resError {
            case .emptyContacts:
                return NSLocalizedString("This feed requires contacts, but your contact list is empty. Follow some people first.", comment: "Error when a spell feed needs contacts but the user follows nobody")
            case .emptyFilter:
                return NSLocalizedString("Could not build a valid filter for this feed.", comment: "Error when a spell feed's filter is invalid")
            case .filterConversionFailed:
                return NSLocalizedString("Could not convert this feed's filter for the local database.", comment: "Error when a spell feed's filter cannot be converted to NdbFilter")
            }
        case .invalidRelayURL(let url):
            return String(format: NSLocalizedString("Invalid relay URL: %@", comment: "Error when a spell specifies an invalid relay URL"), url)
        }
    }
}
