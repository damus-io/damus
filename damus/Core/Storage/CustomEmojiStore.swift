//
//  CustomEmojiStore.swift
//  damus
//
//  Created for NIP-30 custom emoji support.
//

import Foundation

/// Stores and manages custom emojis seen from the timeline for use in compose.
///
/// This store collects custom emojis from events the user encounters,
/// making them available for selection when composing new posts.
class CustomEmojiStore: ObservableObject {
    /// All known custom emojis, keyed by shortcode for deduplication.
    @Published private(set) var emojis: [String: CustomEmoji] = [:]

    /// Returns all emojis sorted alphabetically by shortcode.
    var sortedEmojis: [CustomEmoji] {
        emojis.values.sorted { $0.shortcode.lowercased() < $1.shortcode.lowercased() }
    }

    /// Returns the count of known emojis.
    var count: Int {
        emojis.count
    }

    /// Adds a custom emoji to the store.
    ///
    /// - Parameter emoji: The custom emoji to add.
    func add(_ emoji: CustomEmoji) {
        emojis[emoji.shortcode] = emoji
    }

    /// Adds multiple custom emojis to the store.
    ///
    /// - Parameter newEmojis: Collection of custom emojis to add.
    func add<C: Collection>(contentsOf newEmojis: C) where C.Element == CustomEmoji {
        for emoji in newEmojis {
            emojis[emoji.shortcode] = emoji
        }
    }

    /// Collects custom emojis from an event and adds them to the store.
    ///
    /// - Parameter event: The event to extract emojis from.
    func collect(from event: NostrEvent) {
        let eventEmojis = Array(event.referenced_custom_emojis)
        guard !eventEmojis.isEmpty else { return }
        add(contentsOf: eventEmojis)
    }

    /// Looks up an emoji by shortcode.
    ///
    /// - Parameter shortcode: The shortcode to look up.
    /// - Returns: The custom emoji if found, nil otherwise.
    func emoji(for shortcode: String) -> CustomEmoji? {
        emojis[shortcode]
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

    /// Clears all stored emojis.
    func clear() {
        emojis.removeAll()
    }
}
