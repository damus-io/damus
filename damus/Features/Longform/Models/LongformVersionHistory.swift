//
//  LongformVersionHistory.swift
//  damus
//
//  Created for issue #3517 - Display longform article edit history
//

import Foundation

/// Represents the version history of a longform article (kind 30023).
///
/// Longform articles are addressable events identified by kind + pubkey + d-tag.
/// Each edit creates a new event with a new id but the same address coordinates.
/// This struct queries nostrdb for all versions we've seen of a given article.
struct LongformVersionHistory {
    /// All versions of the article, sorted by created_at descending (newest first)
    let versions: [NostrEvent]

    /// The d-tag identifier for this article
    let identifier: String

    /// The author's pubkey
    let author: Pubkey

    /// Whether this article has been edited (more than one version exists)
    var hasBeenEdited: Bool {
        versions.count > 1
    }

    /// The number of edits (versions - 1, since the first version isn't an edit)
    var editCount: Int {
        max(0, versions.count - 1)
    }

    /// The latest (current) version of the article
    var currentVersion: NostrEvent? {
        versions.first
    }

    /// The original (first) version of the article
    var originalVersion: NostrEvent? {
        versions.last
    }

    /// Query nostrdb for all versions of a longform article.
    ///
    /// This method runs database queries off the main thread to avoid blocking UI.
    ///
    /// - Parameters:
    ///   - event: The longform event to find history for
    ///   - ndb: The nostrdb instance to query
    /// - Returns: A LongformVersionHistory containing all versions, or nil if the event
    ///           is not a longform article or has no d-tag
    static func fetch(for event: NostrEvent, ndb: Ndb) async -> LongformVersionHistory? {
        guard event.known_kind == .longform else {
            return nil
        }

        guard let identifier = event.referenced_params.first?.param.string() else {
            return nil
        }

        return await fetch(author: event.pubkey, identifier: identifier, ndb: ndb)
    }

    /// Query nostrdb for all versions of a longform article by its address coordinates.
    ///
    /// This method runs database queries off the main thread to avoid blocking UI.
    ///
    /// - Parameters:
    ///   - author: The pubkey of the article author
    ///   - identifier: The d-tag identifier of the article
    ///   - ndb: The nostrdb instance to query
    /// - Returns: A LongformVersionHistory containing all versions, or nil on error
    static func fetch(author: Pubkey, identifier: String, ndb: Ndb) async -> LongformVersionHistory? {
        return await Task.detached(priority: .userInitiated) {
            fetchSync(author: author, identifier: identifier, ndb: ndb)
        }.value
    }

    /// Synchronous version of fetch for internal use.
    /// Callers should use the async version to avoid blocking the main thread.
    private static func fetchSync(author: Pubkey, identifier: String, ndb: Ndb) -> LongformVersionHistory? {
        let filter = NostrFilter(
            kinds: [.longform],
            authors: [author],
            parameter: [identifier]
        )

        guard let ndbFilter = try? NdbFilter(from: filter),
              let noteKeys = try? ndb.query(filters: [ndbFilter], maxResults: 1000) else {
            return nil
        }

        let events = noteKeys.compactMap { noteKey -> NostrEvent? in
            try? ndb.lookup_note_by_key_and_copy(noteKey)
        }.sorted { $0.created_at > $1.created_at }

        return LongformVersionHistory(
            versions: events,
            identifier: identifier,
            author: author
        )
    }
}

/// Extension to get version info for a longform event
extension LongformEvent {
    /// Fetch the version history for this longform article.
    /// This method is async to avoid blocking the main thread.
    func fetchVersionHistory(ndb: Ndb) async -> LongformVersionHistory? {
        return await LongformVersionHistory.fetch(for: event, ndb: ndb)
    }
}
