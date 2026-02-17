//
//  GroupedTimelineGrouper.swift
//  damus
//
//  Created by alltheseas on 2025-12-07.
//

import Foundation

// MARK: - Author Group Model

/// Represents an aggregated group of posts from a single author.
/// Used by the grouped view to show one row per author with their post count.
struct AuthorGroup: Identifiable {
    let pubkey: Pubkey
    let latestEvent: NostrEvent
    let postCount: Int

    var id: Pubkey { pubkey }
}

// MARK: - Filter Value Snapshot

/// Value-type snapshot of filter inputs for deterministic, testable grouping.
/// Decouples the grouping logic from the `ObservableObject` reference type.
struct GroupedFilterValues {
    let timeRangeSeconds: UInt32
    let includeReplies: Bool
    let hideShortNotes: Bool
    let filteredWords: String
    let maxNotesPerUser: Int?
}

extension GroupedFilterSettings {
    var filterValues: GroupedFilterValues {
        GroupedFilterValues(
            timeRangeSeconds: timeRange.seconds,
            includeReplies: includeReplies,
            hideShortNotes: hideShortNotes,
            filteredWords: filteredWords,
            maxNotesPerUser: maxNotesPerUser
        )
    }
}

// MARK: - Grouped Timeline Grouper

/// Pure-function grouping and filtering logic extracted from the view for testability.
/// All methods are static and take value-type inputs — no reference types or SwiftUI dependencies.
struct GroupedTimelineGrouper {

    /// Groups events by author, applying all filters, and returns sorted author groups.
    static func group(
        events: [NostrEvent],
        filter: (NostrEvent) -> Bool,
        values: GroupedFilterValues,
        now: Date = Date()
    ) -> [AuthorGroup] {
        let wordsList = parseFilteredWords(values.filteredWords)
        let epoch = UInt32(now.timeIntervalSince1970)
        let cutoff = epoch > values.timeRangeSeconds ? epoch - values.timeRangeSeconds : 0

        var groupsByAuthor: [Pubkey: (latest: NostrEvent, count: Int)] = [:]

        for event in events {
            guard shouldIncludeEvent(event, filter: filter, values: values, wordsList: wordsList, cutoff: cutoff) else { continue }

            if let existing = groupsByAuthor[event.pubkey] {
                let newLatest = event.created_at > existing.latest.created_at ? event : existing.latest
                groupsByAuthor[event.pubkey] = (latest: newLatest, count: existing.count + 1)
            } else {
                groupsByAuthor[event.pubkey] = (latest: event, count: 1)
            }
        }

        if let maxNotes = values.maxNotesPerUser {
            groupsByAuthor = groupsByAuthor.filter { $0.value.count <= maxNotes }
        }

        return groupsByAuthor
            .map { AuthorGroup(pubkey: $0.key, latestEvent: $0.value.latest, postCount: $0.value.count) }
            .sorted {
                if $0.latestEvent.created_at != $1.latestEvent.created_at {
                    return $0.latestEvent.created_at > $1.latestEvent.created_at
                }
                return $0.pubkey.id.lexicographicallyPrecedes($1.pubkey.id)
            }
    }

    // MARK: - Internal Filtering

    static func parseFilteredWords(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.count >= 2 }
    }

    static func shouldIncludeEvent(
        _ event: NostrEvent,
        filter: (NostrEvent) -> Bool,
        values: GroupedFilterValues,
        wordsList: [String],
        cutoff: UInt32
    ) -> Bool {
        guard event.created_at >= cutoff else { return false }
        guard filter(event) else { return false }
        if !values.includeReplies && event.is_reply() { return false }
        if containsFilteredWords(event, wordsList: wordsList) { return false }
        if isTooShort(event, hideShortNotes: values.hideShortNotes) { return false }
        return true
    }

    static func containsFilteredWords(_ event: NostrEvent, wordsList: [String]) -> Bool {
        guard !wordsList.isEmpty else { return false }
        let content = event.content.lowercased()
        return wordsList.contains { content.contains($0) }
    }

    static func isTooShort(_ event: NostrEvent, hideShortNotes: Bool) -> Bool {
        guard hideShortNotes else { return false }

        let content = event.content.trimmingCharacters(in: .whitespacesAndNewlines)

        if content.count < 10 { return true }

        let textWithoutEmojis = content.unicodeScalars
            .filter { !$0.properties.isEmojiPresentation }
            .map { String($0) }
            .joined()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if textWithoutEmojis.count < 2 { return true }

        let words = content.split(whereSeparator: { $0.isWhitespace }).filter { !$0.isEmpty }
        if words.count == 1 && content.count < 20 { return true }

        return false
    }
}
