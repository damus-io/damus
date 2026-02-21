//
//  GroupedFilterButton.swift
//  damus
//
//  Created by alltheseas on 2025-12-08.
//

import SwiftUI

// MARK: - Time Range

/// Time range options for filtering grouped feed events.
/// Controls how far back in time to display notes.
enum GroupedTimeRange: String, CaseIterable {
    case day = "24h"
    case week = "7d"

    /// Duration in seconds for relay query filtering.
    var seconds: UInt32 {
        switch self {
        case .day:  return 24 * 60 * 60      // 86,400 seconds
        case .week: return 7 * 24 * 60 * 60  // 604,800 seconds
        }
    }

    /// Short label for display in the filter button (e.g., "24h", "7d").
    var localizedTitle: String {
        switch self {
        case .day:
            return NSLocalizedString("24h", comment: "Filter option for last 24 hours")
        case .week:
            return NSLocalizedString("7d", comment: "Filter option for last 7 days")
        }
    }

    /// Full label for display in settings (e.g., "24 Hours", "7 Days").
    var displayTitle: String {
        switch self {
        case .day:
            return NSLocalizedString("24 Hours", comment: "Time range option for last 24 hours")
        case .week:
            return NSLocalizedString("7 Days", comment: "Time range option for last 7 days")
        }
    }
}

// MARK: - Filter Button

/// A compact pill-style button that displays the current filter state and opens the settings sheet.
/// Shows the view mode (Grouped/Timeline) and time range (24h/7d) at a glance.
///
/// Example appearance: `[≡ Grouped · 24h]`
struct GroupedFilterButton: View {
    @ObservedObject var settings: GroupedFilterSettings
    @Binding var showFilterSheet: Bool

    /// When true, shows a loading spinner (used during background data fetches).
    var isLoading: Bool = false

    var body: some View {
        Button {
            showFilterSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.footnote)

                Text(filterSummary)
                    .font(.footnote)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    /// Generates a concise summary string like "Grouped · 24h" for the button label.
    private var filterSummary: String {
        let mode = settings.enableGroupedMode
            ? NSLocalizedString("Grouped", comment: "Filter mode label for grouped view")
            : NSLocalizedString("Timeline", comment: "Filter mode label for timeline view")
        let time = settings.timeRange.localizedTitle
        return "\(mode) · \(time)"
    }
}

#Preview {
    VStack {
        GroupedFilterButton(
            settings: GroupedFilterSettings(),
            showFilterSheet: .constant(false)
        )
        .background(Color.black)
    }
}
