//
//  ScrollPositionManager.swift
//  damus
//
//  Created for GitHub issue #3393: Remember My Spot
//
//  This manager tracks and restores scroll positions across the app.
//  It uses anchor-based tracking (event IDs) rather than pixel offsets,
//  so positions remain valid even when new content loads above.
//

import Foundation

/// Represents a saved scroll position in a timeline or list view.
///
/// We store the event ID rather than a pixel offset because:
/// - New posts can appear above the saved position
/// - The timeline can be refreshed with different content
/// - Event IDs remain stable across app launches
struct ScrollPosition: Codable, Equatable {
    /// The ID of the event that was visible at the top of the viewport
    let anchorEventId: String

    /// When this position was saved (for expiry/cleanup)
    let savedAt: Date

    /// Maximum age before a saved position is considered stale (24 hours)
    static let maxAge: TimeInterval = 60 * 60 * 24

    var isExpired: Bool {
        Date().timeIntervalSince(savedAt) > Self.maxAge
    }
}

/// Identifies which view's scroll position we're tracking.
///
/// Each timeline/view type gets its own saved position.
/// Using an enum ensures type safety and prevents typos in string keys.
enum ScrollPositionKey: String, Codable, CaseIterable {
    case homeTimeline = "home"
    case notifications = "notifications"
    case search = "search"
    case dms = "dms"

    /// Create a key from the Timeline enum used elsewhere in the app
    init?(timeline: Timeline) {
        switch timeline {
        case .home: self = .homeTimeline
        case .notifications: self = .notifications
        case .search: self = .search
        case .dms: self = .dms
        }
    }
}

/// Manages scroll position persistence across the app.
///
/// Design decisions:
/// - Uses UserDefaults for simplicity (positions are small, ~100 bytes each)
/// - Positions keyed by view identifier (timeline type)
/// - Automatic cleanup of expired positions on load
///
/// Usage:
/// ```swift
/// // Save position when leaving a view
/// scrollManager.save(eventId: "abc123", for: .homeTimeline)
///
/// // Restore position when returning
/// if let position = scrollManager.position(for: .homeTimeline) {
///     scrollTo(position.anchorEventId)
/// }
/// ```
final class ScrollPositionManager {

    // MARK: - Storage

    private static let storageKey = "scroll_positions_v1"

    /// In-memory cache of positions, synced to UserDefaults
    private(set) var positions: [ScrollPositionKey: ScrollPosition] = [:]

    // MARK: - Initialization

    init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// Save the current scroll position for a view.
    ///
    /// Call this when:
    /// - User switches tabs
    /// - App enters background
    /// - User navigates into a detail view
    func save(eventId: String, for key: ScrollPositionKey) {
        let position = ScrollPosition(anchorEventId: eventId, savedAt: Date())
        positions[key] = position
        persistToDisk()
    }

    /// Get the saved scroll position for a view, if any.
    ///
    /// Returns nil if:
    /// - No position was saved
    /// - The saved position has expired (>24 hours old)
    func position(for key: ScrollPositionKey) -> ScrollPosition? {
        guard let position = positions[key] else { return nil }
        guard !position.isExpired else {
            // Clean up expired position
            positions.removeValue(forKey: key)
            persistToDisk()
            return nil
        }
        return position
    }

    /// Clear the saved position for a view.
    ///
    /// Call this when the user explicitly scrolls to top (e.g., taps tab bar).
    func clear(for key: ScrollPositionKey) {
        positions.removeValue(forKey: key)
        persistToDisk()
    }

    /// Clear all saved positions.
    func clearAll() {
        positions.removeAll()
        persistToDisk()
    }

    // MARK: - Persistence

    private func persistToDisk() {
        guard let data = try? JSONEncoder().encode(positions) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([ScrollPositionKey: ScrollPosition].self, from: data) else { return }

        // Filter out expired positions during load
        positions = decoded.filter { !$0.value.isExpired }

        // Persist cleaned-up state if we removed any expired positions
        if positions.count != decoded.count {
            persistToDisk()
        }
    }
}
