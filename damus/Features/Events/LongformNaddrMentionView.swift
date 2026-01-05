//
//  LongformNaddrMentionView.swift
//  damus
//
//  Created by alltheseas on 2026-01-04.
//

import SwiftUI

/// A view that displays a longform article preview for an naddr mention.
/// Loads the referenced addressable event asynchronously and renders it as a LongformPreview card.
/// Falls back to an abbreviated link if the event cannot be loaded.
struct LongformNaddrMentionView: View {
    let damus_state: DamusState
    let naddr: NAddr

    @State private var loadState: LoadState = .loading

    enum LoadState {
        case loading
        case loaded(NostrEvent)
        case notFound
    }

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                loadingView
            case .loaded(let event):
                NavigationLink(value: Route.Thread(thread: ThreadModel(event: event, damus_state: damus_state))) {
                    LongformPreview(state: damus_state, ev: event, options: [.truncate_content, .no_action_bar])
                }
                .buttonStyle(.plain)
            case .notFound:
                // Fall back to abbreviated text link
                fallbackLinkView
            }
        }
        .task {
            await loadEvent()
        }
    }

    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading article...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(DamusColors.neutral1)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1.0)
        )
    }

    private var fallbackLinkView: some View {
        let bech32 = Bech32Object.encode(.naddr(naddr))
        return Text("@\(abbrev_identifier(bech32))")
            .foregroundColor(DamusColors.purple)
    }

    private func loadEvent() async {
        // Try to look up the naddr event
        if let event = await damus_state.nostrNetwork.reader.lookup(naddr: naddr) {
            await MainActor.run {
                loadState = .loaded(event)
            }
        } else {
            await MainActor.run {
                loadState = .notFound
            }
        }
    }
}

/// A view that displays a longform article preview for a nevent mention.
/// Loads the referenced event by note ID and renders it as a LongformPreview card.
struct LongformNeventMentionView: View {
    let damus_state: DamusState
    let nevent: NEvent

    @State private var loadState: LoadState = .loading

    enum LoadState {
        case loading
        case loaded(NostrEvent)
        case notFound
    }

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                loadingView
            case .loaded(let event):
                NavigationLink(value: Route.Thread(thread: ThreadModel(event: event, damus_state: damus_state))) {
                    LongformPreview(state: damus_state, ev: event, options: [.truncate_content, .no_action_bar])
                }
                .buttonStyle(.plain)
            case .notFound:
                // Fall back to abbreviated text link
                fallbackLinkView
            }
        }
        .task {
            await loadEvent()
        }
    }

    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading article...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(DamusColors.neutral1)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1.0)
        )
    }

    private var fallbackLinkView: some View {
        let bech32 = Bech32Object.encode(.nevent(nevent))
        return Text("@\(abbrev_identifier(bech32))")
            .foregroundColor(DamusColors.purple)
    }

    private func loadEvent() async {
        // Try to look up the event by note ID
        if let lender = try? await damus_state.nostrNetwork.reader.lookup(noteId: nevent.noteid) {
            lender.justUseACopy { event in
                Task { @MainActor in
                    loadState = .loaded(event)
                }
            }
        } else {
            await MainActor.run {
                loadState = .notFound
            }
        }
    }
}
