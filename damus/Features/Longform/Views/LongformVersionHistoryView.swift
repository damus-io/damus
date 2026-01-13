//
//  LongformVersionHistoryView.swift
//  damus
//
//  Created for issue #3517 - Display longform article edit history
//

import SwiftUI

/// A compact view displaying the edit history of a longform article.
///
/// Shows a list of all versions with relative timestamps in a GitHub-style
/// compact format. Tapping a version shows the diff from the previous version.
struct LongformVersionHistoryView: View {
    let state: DamusState
    let history: LongformVersionHistory

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with edit count
                HStack {
                    Text(String(format: NSLocalizedString("Edited %d times", comment: "Header showing number of edits"), history.editCount))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(NSLocalizedString("Most recent", comment: "Label indicating most recent edit is shown first"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(UIColor.secondarySystemBackground))

                // Compact version list
                List {
                    ForEach(Array(history.versions.enumerated()), id: \.element.id) { index, version in
                        let previousVersion = index + 1 < history.versions.count ? history.versions[index + 1] : nil
                        CompactVersionRow(
                            state: state,
                            version: version,
                            previousVersion: previousVersion,
                            isCurrentVersion: index == 0,
                            isOriginalVersion: index == history.versions.count - 1
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle(NSLocalizedString("Edit History", comment: "Title for longform article edit history view"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Done", comment: "Button to dismiss edit history view")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// A compact row showing a single version with relative time.
private struct CompactVersionRow: View {
    let state: DamusState
    let version: NostrEvent
    let previousVersion: NostrEvent?
    let isCurrentVersion: Bool
    let isOriginalVersion: Bool

    @State private var showingDiff: Bool = false
    @State private var showingVersion: Bool = false

    var body: some View {
        Button {
            if previousVersion != nil {
                showingDiff = true
            } else {
                showingVersion = true
            }
        } label: {
            HStack(spacing: 12) {
                // Profile picture
                ProfilePicView(
                    pubkey: version.pubkey,
                    size: 28,
                    highlight: .none,
                    profiles: state.profiles,
                    disable_animation: state.settings.disable_animation,
                    damusState: state
                )

                // Version info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        ProfileName(pubkey: version.pubkey, damus: state)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        if isCurrentVersion {
                            Text(NSLocalizedString("Current", comment: "Label for the current version"))
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .cornerRadius(3)
                        } else if isOriginalVersion {
                            Text(NSLocalizedString("Original", comment: "Label for the original version"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(3)
                        }
                    }

                    Text(relativeTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDiff) {
            if let prevVersion = previousVersion {
                LongformDiffView(oldVersion: prevVersion, newVersion: version)
            }
        }
        .sheet(isPresented: $showingVersion) {
            NavigationStack {
                ScrollView {
                    LongformView(state: state, event: LongformEvent.parse(from: version))
                }
                .navigationTitle(NSLocalizedString("Original Version", comment: "Title for viewing the original article version"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("Done", comment: "Button to dismiss")) {
                            showingVersion = false
                        }
                    }
                }
            }
        }
    }

    /// The relative time string (e.g., "2 days ago").
    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(version.created_at))
        return time_ago_since(date)
    }
}
