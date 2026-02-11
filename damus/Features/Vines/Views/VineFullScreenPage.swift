//
//  VineFullScreenPage.swift
//  damus
//
//  Extracted from PostingTimelineView.swift on 2026-02-10.
//

import SwiftUI

/// Full-screen view of a single Vine video with title, author, summary, and action bar overlay.
struct VineFullScreenPage: View {
    let vine: VineVideo
    let damus_state: DamusState
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = vine.playbackURL ?? vine.fallbackURL {
                DamusVideoPlayerView(url: url, coordinator: damus_state.video, style: .full)
                    .ignoresSafeArea()
            } else {
                Color.black
                Text(NSLocalizedString("Video unavailable", comment: "Fallback text when a Vine video cannot be loaded."))
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(vine.title)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("\(authorLine) • \(relativeDate)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                if let summary = vine.summary {
                    Text(summary)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.top, 4)
                }

                if let fallback = vine.fallbackURL {
                    Button {
                        openURL(fallback)
                    } label: {
                        Label(NSLocalizedString("Open backup stream", comment: "Action to open a fallback Vine video URL when the main stream fails."), systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.2))
                }

                EventActionBar(damus_state: damus_state, event: vine.event, options: [.no_spread])
                    .tint(.white)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.8), Color.black.opacity(0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(vine.altText ?? vine.title))
    }

    private var authorLine: String {
        if let profile = try? damus_state.profiles.lookup(id: vine.event.pubkey) {
            return Profile.displayName(profile: profile, pubkey: vine.event.pubkey).displayName
        }
        return vine.authorDisplay
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var relativeDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(vine.createdAt))
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
