//
//  StoryTrayView.swift
//  damus
//
//  Created by William Casarin on 2026-05-11.
//

import SwiftUI

struct StoryTrayContainerView: View {
    let damus_state: DamusState
    @StateObject private var stories: StoriesModel
    @State private var selectedAuthor: Pubkey? = nil

    init(damus_state: DamusState) {
        self.damus_state = damus_state
        self._stories = StateObject(wrappedValue: StoriesModel(damus: damus_state))
    }

    var body: some View {
        Group {
            if !stories.tray.isEmpty {
                StoryTrayView(damus_state: damus_state, tray: stories.tray) { pk in
                    selectedAuthor = pk
                }
            }
        }
        .onAppear { stories.subscribe() }
        .onDisappear { stories.unsubscribe() }
        .fullScreenCover(item: Binding(
            get: { selectedAuthor.map { AuthorPick(pubkey: $0) } },
            set: { selectedAuthor = $0?.pubkey }
        )) { pick in
            if let startIndex = stories.tray.firstIndex(where: { $0.author == pick.pubkey }) {
                StoryViewerView(
                    damus_state: damus_state,
                    stories: stories.tray,
                    startAuthorIndex: startIndex,
                    onDismiss: { selectedAuthor = nil }
                )
            }
        }
    }
}

private struct AuthorPick: Identifiable {
    let pubkey: Pubkey
    var id: Pubkey { pubkey }
}

struct StoryTrayView: View {
    let damus_state: DamusState
    let tray: [Story]
    let onTap: (Pubkey) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(tray) { story in
                    StoryTrayItem(damus_state: damus_state, story: story)
                        .onTapGesture { onTap(story.author) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

private struct StoryTrayItem: View {
    let damus_state: DamusState
    let story: Story

    private let avatarSize: CGFloat = 60

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [DamusColors.purple, .pink, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: avatarSize + 8, height: avatarSize + 8)

                ProfilePicView(
                    pubkey: story.author,
                    size: avatarSize,
                    highlight: .none,
                    profiles: damus_state.profiles,
                    disable_animation: damus_state.settings.disable_animation,
                    damusState: damus_state
                )
            }
        }
        .frame(width: avatarSize + 14)
    }
}
