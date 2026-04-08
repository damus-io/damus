//
//  FeedTab.swift
//  damus
//
//  Model for feed tabs in the multi-feed tab bar.
//

import Foundation

/// Represents a tab in the feed tab bar.
///
/// Each tab is either the built-in "Following" feed or a spell feed
/// defined by a kind:777 event.
enum FeedTab: Identifiable, Equatable, Hashable {
    /// The built-in "Following" feed.
    case following
    /// A spell-based custom feed.
    case spell(SavedSpellFeed)

    var id: String {
        switch self {
        case .following:
            return "following"
        case .spell(let saved):
            return saved.id
        }
    }

    var label: String {
        switch self {
        case .following:
            return NSLocalizedString("Following", comment: "Label for the Following feed tab")
        case .spell(let saved):
            return saved.name
        }
    }
}

/// A spell feed saved by the user, persisted to UserDefaults.
struct SavedSpellFeed: Identifiable, Equatable, Hashable, Codable {
    /// Unique identifier (the kind:777 event's note ID hex, or a generated UUID for starters).
    let id: String
    /// Short display name for the tab (1-2 words).
    let name: String
    /// The full spell event JSON used to reconstruct the SpellEvent.
    let spellEventJSON: String

    /// Decodes the saved spell event JSON into a NostrEvent, then parses it.
    func parseSpell() -> SpellEvent? {
        guard let event = NostrEvent.owned_from_json(json: spellEventJSON) else {
            return nil
        }
        return SpellEvent.parse(from: event)
    }
}
