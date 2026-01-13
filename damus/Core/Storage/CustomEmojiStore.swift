//
//  CustomEmojiStore.swift
//  damus
//
//  Created for NIP-30 custom emoji support.
//

import Foundation

/// Stores and manages custom emojis for use in compose.
///
/// This store has two sources of emojis:
/// 1. **Saved emojis** - User's personal collection stored as kind 10030 event (persistent)
/// 2. **Recent emojis** - Collected from events the user encounters on timeline (ephemeral)
@MainActor
class CustomEmojiStore: ObservableObject {
    /// User's saved emojis from kind 10030 event, keyed by shortcode.
    @Published private(set) var savedEmojis: [String: CustomEmoji] = [:]

    /// Recently seen emojis from timeline, keyed by shortcode.
    @Published private(set) var recentEmojis: [String: CustomEmoji] = [:]

    /// The current kind 10030 event (if loaded).
    private(set) var emojiListEvent: NostrEvent? = nil

    /// Returns saved emojis sorted alphabetically by shortcode.
    var sortedSavedEmojis: [CustomEmoji] {
        savedEmojis.values.sorted { $0.shortcode.lowercased() < $1.shortcode.lowercased() }
    }

    /// Returns recent emojis sorted alphabetically by shortcode.
    var sortedRecentEmojis: [CustomEmoji] {
        recentEmojis.values.sorted { $0.shortcode.lowercased() < $1.shortcode.lowercased() }
    }

    /// Returns all emojis (saved + recent, deduplicated) sorted alphabetically.
    var sortedEmojis: [CustomEmoji] {
        var combined = savedEmojis
        for (shortcode, emoji) in recentEmojis {
            if combined[shortcode] == nil {
                combined[shortcode] = emoji
            }
        }
        return combined.values.sorted { $0.shortcode.lowercased() < $1.shortcode.lowercased() }
    }

    /// Returns the count of saved emojis.
    var savedCount: Int {
        savedEmojis.count
    }

    /// Returns the count of recent emojis.
    var recentCount: Int {
        recentEmojis.count
    }

    /// Returns total count of all known emojis.
    var count: Int {
        sortedEmojis.count
    }

    nonisolated init() {}

    // MARK: - Saved Emojis (kind 10030)

    /// Sets the emoji list from a kind 10030 event.
    ///
    /// - Parameter event: The kind 10030 emoji list event.
    func setEmojiList(_ event: NostrEvent) {
        guard event.known_kind == .emoji_list else { return }

        // Only update if this event is newer
        if let existing = emojiListEvent, existing.created_at >= event.created_at {
            return
        }

        emojiListEvent = event

        // Parse emoji tags from the event
        var newSaved: [String: CustomEmoji] = [:]
        for emoji in event.referenced_custom_emojis {
            newSaved[emoji.shortcode] = emoji
        }
        savedEmojis = newSaved
    }

    /// Checks if an emoji is saved.
    ///
    /// - Parameter shortcode: The shortcode to check.
    /// - Returns: True if the emoji is in the saved collection.
    func isSaved(_ shortcode: String) -> Bool {
        savedEmojis[shortcode] != nil
    }

    /// Checks if an emoji is saved.
    ///
    /// - Parameter emoji: The emoji to check.
    /// - Returns: True if the emoji is in the saved collection.
    func isSaved(_ emoji: CustomEmoji) -> Bool {
        savedEmojis[emoji.shortcode] != nil
    }

    /// Saves an emoji to the user's collection (local only, call publish separately).
    ///
    /// - Parameter emoji: The emoji to save.
    func save(_ emoji: CustomEmoji) {
        savedEmojis[emoji.shortcode] = emoji
    }

    /// Removes an emoji from the user's collection (local only, call publish separately).
    ///
    /// - Parameter shortcode: The shortcode of the emoji to remove.
    func unsave(_ shortcode: String) {
        savedEmojis.removeValue(forKey: shortcode)
    }

    /// Removes an emoji from the user's collection (local only, call publish separately).
    ///
    /// - Parameter emoji: The emoji to remove.
    func unsave(_ emoji: CustomEmoji) {
        savedEmojis.removeValue(forKey: emoji.shortcode)
    }

    /// Creates a new kind 10030 event with the current saved emojis.
    ///
    /// - Parameter keypair: The keypair to sign the event.
    /// - Returns: A signed NostrEvent, or nil if signing fails.
    nonisolated func createEmojiListEvent(keypair: FullKeypair, emojis: [CustomEmoji]) -> NostrEvent? {
        let tags: [[String]] = emojis.map { $0.tag }
        return NostrEvent(
            content: "",
            keypair: keypair.to_keypair(),
            kind: NostrKind.emoji_list.rawValue,
            tags: tags
        )
    }

    // MARK: - Recent Emojis (from timeline)

    /// Adds a custom emoji to the recent collection.
    ///
    /// - Parameter emoji: The custom emoji to add.
    func add(_ emoji: CustomEmoji) {
        recentEmojis[emoji.shortcode] = emoji
    }

    /// Adds multiple custom emojis to the recent collection.
    ///
    /// - Parameter newEmojis: Collection of custom emojis to add.
    func add<C: Collection>(contentsOf newEmojis: C) where C.Element == CustomEmoji {
        for emoji in newEmojis {
            recentEmojis[emoji.shortcode] = emoji
        }
    }

    /// Collects custom emojis from an event and adds them to the recent collection.
    ///
    /// - Parameter event: The event to extract emojis from.
    func collect(from event: NostrEvent) {
        let eventEmojis = Array(event.referenced_custom_emojis)
        guard !eventEmojis.isEmpty else { return }
        add(contentsOf: eventEmojis)
    }

    // MARK: - Lookup & Search

    /// Looks up an emoji by shortcode (checks saved first, then recent).
    ///
    /// - Parameter shortcode: The shortcode to look up.
    /// - Returns: The custom emoji if found, nil otherwise.
    func emoji(for shortcode: String) -> CustomEmoji? {
        savedEmojis[shortcode] ?? recentEmojis[shortcode]
    }

    /// Searches emojis by shortcode prefix.
    ///
    /// - Parameter query: The search query (prefix match on shortcode).
    /// - Returns: Array of matching emojis sorted alphabetically.
    func search(_ query: String) -> [CustomEmoji] {
        guard !query.isEmpty else { return sortedEmojis }
        let lowercaseQuery = query.lowercased()
        return sortedEmojis.filter { $0.shortcode.lowercased().hasPrefix(lowercaseQuery) }
    }

    /// Searches only saved emojis by shortcode prefix.
    ///
    /// - Parameter query: The search query (prefix match on shortcode).
    /// - Returns: Array of matching saved emojis sorted alphabetically.
    func searchSaved(_ query: String) -> [CustomEmoji] {
        guard !query.isEmpty else { return sortedSavedEmojis }
        let lowercaseQuery = query.lowercased()
        return sortedSavedEmojis.filter { $0.shortcode.lowercased().hasPrefix(lowercaseQuery) }
    }

    /// Searches only recent emojis by shortcode prefix.
    ///
    /// - Parameter query: The search query (prefix match on shortcode).
    /// - Returns: Array of matching recent emojis sorted alphabetically.
    func searchRecent(_ query: String) -> [CustomEmoji] {
        guard !query.isEmpty else { return sortedRecentEmojis }
        let lowercaseQuery = query.lowercased()
        return sortedRecentEmojis.filter { $0.shortcode.lowercased().hasPrefix(lowercaseQuery) }
    }

    /// Clears recent emojis (not saved ones).
    func clearRecent() {
        recentEmojis.removeAll()
    }
}
