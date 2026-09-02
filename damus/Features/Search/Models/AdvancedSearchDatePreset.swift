//
//  AdvancedSearchDatePreset.swift
//  damus
//
//  Created by William Casarin on 2026-09-02.
//

import Foundation

/// The date windows the filter sheet offers as one tap.
///
/// The presets are what make the date filter feel fast; the custom pickers are
/// the escape hatch.
///
/// Every preset is an open-ended window: it sets `since` to a day boundary and
/// leaves `until` unset. See ``window(now:calendar:)`` for why.
enum AdvancedSearchDatePreset: String, CaseIterable, Identifiable, Hashable {
    case allTime
    case today
    case last7Days
    case last30Days
    case thisYear
    /// Not offered as a tap — this is what the picker reports when the query's
    /// window matches no preset, which is how the custom pickers stay reachable
    /// without a second piece of state saying "custom is showing".
    case custom

    var id: String { rawValue }

    /// The presets a picker should show, which is every one but ``custom``.
    static var selectable: [AdvancedSearchDatePreset] {
        allCases.filter({ $0 != .custom })
    }

    var label: String {
        switch self {
        case .allTime: return NSLocalizedString("All time", comment: "Search date range preset covering every note.")
        case .today: return NSLocalizedString("Today", comment: "Search date range preset covering today only.")
        case .last7Days: return NSLocalizedString("Last 7 days", comment: "Search date range preset covering the last seven days.")
        case .last30Days: return NSLocalizedString("Last 30 days", comment: "Search date range preset covering the last thirty days.")
        case .thisYear: return NSLocalizedString("This year", comment: "Search date range preset covering the current calendar year.")
        case .custom: return NSLocalizedString("Custom", comment: "Search date range option for picking exact dates.")
        }
    }

    /// The window this preset means, or `nil` for ``custom``, which has no window
    /// of its own.
    ///
    /// `until` is left `nil` rather than pinned to now: a query with no upper
    /// bound is one nostrdb can seek from the end of the index, and pinning "now"
    /// would go stale the moment the sheet was left open.
    func window(now: Date = Date(), calendar: Calendar? = nil) -> (since: Date?, until: Date?)? {
        let calendar = calendar ?? AdvancedSearchQueryDSL.defaultCalendar
        let startOfToday = calendar.startOfDay(for: now)

        switch self {
        case .allTime:
            return (nil, nil)
        case .today:
            return (startOfToday, nil)
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -6, to: startOfToday), nil)
        case .last30Days:
            return (calendar.date(byAdding: .day, value: -29, to: startOfToday), nil)
        case .thisYear:
            var components = calendar.dateComponents([.year], from: now)
            components.month = 1
            components.day = 1
            return (calendar.date(from: components), nil)
        case .custom:
            return nil
        }
    }

    /// Which preset `query`'s window is, or ``custom`` when it is none of them.
    ///
    /// Matching on the resolved window rather than remembering what was tapped is
    /// what lets the sheet and the DSL text stay the same state: a `since:7d`
    /// typed into the field lights up the same chip the sheet would have set.
    static func matching(_ query: AdvancedSearchQuery,
                         now: Date = Date(),
                         calendar: Calendar? = nil) -> AdvancedSearchDatePreset {
        for preset in selectable {
            guard let window = preset.window(now: now, calendar: calendar) else { continue }
            if window.since == query.since && window.until == query.until { return preset }
        }
        return .custom
    }

    /// `query` with this preset's window applied. ``custom`` leaves it alone.
    func applied(to query: AdvancedSearchQuery,
                 now: Date = Date(),
                 calendar: Calendar? = nil) -> AdvancedSearchQuery {
        guard let window = window(now: now, calendar: calendar) else { return query }
        var query = query
        query.since = window.since
        query.until = window.until
        return query
    }
}
