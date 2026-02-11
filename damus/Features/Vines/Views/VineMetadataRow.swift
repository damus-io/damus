//
//  VineMetadataRow.swift
//  damus
//
//  Extracted from PostingTimelineView.swift on 2026-02-10.
//

import SwiftUI

/// Compact icon + text row used for Vine video metadata (duration, dimensions, loop count, etc.).
struct VineMetadataRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
