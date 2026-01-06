//
//  LongformNaddrMentionView.swift
//  damus
//
//  Created by alltheseas + jb55 on 2026-01-04.
//

import SwiftUI

/// A view that displays a longform article preview for a reference (naddr or nevent).
/// Loads asynchronously and renders as a LongformPreview card, with a text fallback if not found.
struct LongformMentionView: View {
    let damus_state: DamusState
    let reference: LongformReference

    @State private var loadState: LoadState = .loading

    private enum LoadState {
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
                NavigationLink(
                    value: Route.Thread(thread: ThreadModel(event: event, damus_state: damus_state))
                ) {
                    LongformPreview(state: damus_state, ev: event, options: [.truncate_content, .no_action_bar])
                }
                .buttonStyle(.plain)

            case .notFound:
                fallbackLinkView
            }
        }
        .task {
            await loadEvent()
        }
    }

    private var fallbackLinkView: some View {
        Text("@\(abbrev_identifier(bech32))")
            .foregroundColor(DamusColors.purple)
    }

    private var bech32: String {
        switch reference {
        case .naddr(let naddr):
            return Bech32Object.encode(.naddr(naddr))
        case .nevent(let nevent):
            return Bech32Object.encode(.nevent(nevent))
        }
    }

    private func loadEvent() async {
        switch reference {
        case .naddr(let naddr):
            if let event = await damus_state.nostrNetwork.reader.lookup(naddr: naddr) {
                await MainActor.run { loadState = .loaded(event) }
            } else {
                await MainActor.run { loadState = .notFound }
            }

        case .nevent(let nevent):
            if let lender = try? await damus_state.nostrNetwork.reader.lookup(noteId: nevent.noteid) {
                // Preserve the existing copy semantics
                let event: NostrEvent = await withCheckedContinuation { continuation in
                    lender.justUseACopy { ev in
                        continuation.resume(returning: ev)
                    }
                }
                await MainActor.run { loadState = .loaded(event) }
            } else {
                await MainActor.run { loadState = .notFound }
            }
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
}

/// A preview card for longform articles in compose view with a delete button.
/// Displays the article preview and allows the user to remove the reference.
struct LongformPreviewCard: View {
    let damus_state: DamusState
    let reference: LongformReference
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LongformMentionView(damus_state: damus_state, reference: reference)
            deleteButton
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image("close-circle")
                .foregroundColor(.white)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .shadow(radius: 5)
        }
        .padding(8)
    }
}

/// A horizontal carousel for longform article previews in compose view.
/// Similar to the image carousel, allows scrolling through multiple articles with individual delete buttons.
struct LongformCarouselView: View {
    let damus_state: DamusState
    @Binding var references: [LongformReference]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(references.enumerated()), id: \.offset) { index, ref in
                    LongformPreviewCard(
                        damus_state: damus_state,
                        reference: ref,
                        onDelete: {
                            references.remove(at: index)
                        }
                    )
                    .frame(width: references.count == 1 ? nil : 280)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// A vertical stack for viewing longform article mentions (read-only, no delete buttons).
struct LongformMentionsStack: View {
    let damus_state: DamusState
    let references: [LongformReference]

    var body: some View {
        if references.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                ForEach(Array(references.enumerated()), id: \.offset) { _, ref in
                    LongformMentionView(damus_state: damus_state, reference: ref)
                }
            }
        }
    }
}
