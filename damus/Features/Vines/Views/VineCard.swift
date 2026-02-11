//
//  VineCard.swift
//  damus
//
//  Extracted from PostingTimelineView.swift on 2026-02-10.
//

import SwiftUI

/// Card view for a single Vine video: header, video player preview, metadata rows, and action bar.
struct VineCard: View {
    private static let videoPreviewHeight: CGFloat = 320

    let vine: VineVideo
    let damus_state: DamusState
    let onAppear: () -> Void
    let onOpenFullScreen: () -> Void
    @State private var isSensitiveRevealed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            videoBody
            metadataRows
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .onAppear(perform: onAppear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(vine.altText ?? vine.title))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vine.title)
                    .font(.headline)
                Text("\(authorDisplayName) • \(relativeDate)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                if let repostedBy = vine.repostedBy {
                    Text(String(format: NSLocalizedString("Reposted by %@", comment: "Label showing the author who reposted a Vine video."), repostedBy))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Menu {
                Button {
                    reportVine()
                } label: {
                    Label(NSLocalizedString("Report Vine", comment: "Menu action to report a Vine video."), systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("More actions", comment: "Accessibility label for the Vine card overflow menu."))
        }
    }

    private var videoBody: some View {
        ZStack {
            if let url = vine.playbackURL {
                DamusVideoPlayerView(url: url, coordinator: damus_state.video, style: .preview(on_tap: onOpenFullScreen))
                    .frame(height: Self.videoPreviewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                Color.gray.opacity(0.2)
                    .frame(height: Self.videoPreviewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(NSLocalizedString("Video unavailable", comment: "Fallback text when a Vine video cannot be loaded."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if shouldBlurContent {
                Color.black.opacity(0.5)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                VStack {
                    Image(systemName: "eye.slash")
                        .font(.title2)
                        .foregroundColor(.white)
                    if let warning = vine.contentWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.top, 2)
                    }
                    Button(NSLocalizedString("Reveal", comment: "Button to reveal sensitive Vine content.")) {
                        isSensitiveRevealed = true
                    }
                    .padding(.top, 8)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let warning = vine.contentWarning, !shouldBlurContent {
                Label(warning, systemImage: "eye.trianglebadge.exclamationmark")
                    .font(.caption2.weight(.semibold))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
        }
    }

    private var metadataRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = vine.summary {
                Text(summary)
                    .font(.body)
            }

            if let alt = vine.altText {
                Text(alt)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if !vine.hashtags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(vine.hashtags, id: \.self) { hashtag in
                            Text("#\(hashtag)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DamusColors.purple.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if let origin = vine.originDescription {
                VineMetadataRow(icon: "globe", text: origin)
            }

            if let duration = vine.durationDescription {
                VineMetadataRow(icon: "clock", text: duration)
            }

            if let dim = vine.dimensionDescription {
                VineMetadataRow(icon: "aspectratio", text: dim)
            }

            if let loops = vine.loopCount {
                VineMetadataRow(icon: "repeat", text: String(format: NSLocalizedString("%@ loops", comment: "Formatted loop count for a Vine video."), formatCount(loops)))
            }

            if let likes = vine.likeCount {
                VineMetadataRow(icon: "hand.thumbsup", text: String(format: NSLocalizedString("%@ likes", comment: "Formatted like count for a Vine video."), formatCount(likes)))
            }

            if !vine.proofTags.isEmpty {
                VineMetadataRow(icon: "checkmark.seal", text: NSLocalizedString("ProofMode metadata attached", comment: "Label shown when a Vine video has proof tags attached."))
            }

            if let fallback = vine.fallbackURL {
                Button {
                    openURL(fallback)
                } label: {
                    Label(NSLocalizedString("Open backup stream", comment: "Action to open a fallback Vine video URL when the main stream fails."), systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .padding(.vertical, 4)

            EventActionBar(damus_state: damus_state, event: vine.event, options: [.no_spread])
        }
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

    private var shouldBlurContent: Bool {
        guard let _ = vine.contentWarning else { return false }
        return damus_state.settings.hide_nsfw_tagged_content && !isSensitiveRevealed
    }

    private var authorDisplayName: String {
        if let profile = try? damus_state.profiles.lookup(id: vine.event.pubkey) {
            return Profile.displayName(profile: profile, pubkey: vine.event.pubkey).displayName
        }
        return vine.authorDisplay
    }

    private func formatCount(_ value: Int) -> String {
        let number = Double(value)
        let thousand = number / 1_000
        let million = number / 1_000_000
        if million >= 1.0 {
            return String(format: "%.1fM", million)
        } else if thousand >= 1.0 {
            return String(format: "%.1fK", thousand)
        } else {
            return "\(value)"
        }
    }

    private func reportVine() {
        let target = ReportNoteTarget(pubkey: vine.event.pubkey, note_id: vine.event.id)
        notify(.report(.note(target)))
    }
}
