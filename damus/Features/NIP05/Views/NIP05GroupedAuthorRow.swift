//
//  NIP05GroupedAuthorRow.swift
//  damus
//
//  Created by Claude on 2025-12-07.
//

import SwiftUI

/// A row in the grouped view showing an author with their post count
struct NIP05GroupedAuthorRow: View {
    let damus_state: DamusState
    let pubkey: Pubkey
    let latestEvent: NostrEvent
    let postCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ProfilePicView(
                pubkey: pubkey,
                size: 50,
                highlight: .none,
                profiles: damus_state.profiles,
                disable_animation: damus_state.settings.disable_animation,
                damusState: damus_state
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ProfileName(pubkey: pubkey, damus: damus_state, show_nip5_domain: false)
                    Spacer()
                    Text(format_relative_time(latestEvent.created_at))
                        .font(.footnote)
                        .foregroundColor(.gray)
                }

                // Preview of latest post
                Text(eventPreviewText(latestEvent))
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }

            // Post count badge
            postCountBadge
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .contentShape(Rectangle())
    }

    var postCountBadge: some View {
        let fontSize: Font = postCount >= 100 ? .caption2.weight(.medium) : .caption.weight(.medium)
        return Text("\(postCount)")
            .font(fontSize)
            .foregroundColor(DamusColors.purple)
            .frame(minWidth: 28, minHeight: 28)
            .padding(.horizontal, postCount >= 100 ? 4 : 0)
            .background(
                Capsule()
                    .fill(DamusColors.purple.opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(DamusColors.purple.opacity(0.2), lineWidth: 1)
                    )
            )
    }

    /// Extract preview text from an event
    func eventPreviewText(_ event: NostrEvent) -> String {
        let content = event.content

        // Remove nostr: references and clean up
        let cleaned = content
            .replacingOccurrences(of: "nostr:[a-zA-Z0-9]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return NSLocalizedString("(no text content)", comment: "Placeholder for events with no text")
        }

        // Truncate if too long
        if cleaned.count > 150 {
            return String(cleaned.prefix(150)) + "..."
        }

        return cleaned
    }
}

#Preview {
    let damus_state = test_damus_state
    NIP05GroupedAuthorRow(
        damus_state: damus_state,
        pubkey: test_pubkey,
        latestEvent: test_note,
        postCount: 5
    )
}
