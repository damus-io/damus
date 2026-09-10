//
//  InboxRelayResolver.swift
//  damus
//
//  Created by Claude on 2025-03-19.
//

import Foundation

/// Resolves inbox (read) relay URLs for pubkeys tagged in an event.
///
/// Uses only local NDB data — no network fetches. If a tagged user's kind:10002
/// relay list isn't in the database, that user is simply skipped.
struct InboxRelayResolver {
    /// Maximum number of inbox relays to return, to cap fanout on hellthreads.
    static let MAX_INBOX_RELAYS = 6

    /// Resolve inbox relay URLs for all pubkeys p-tagged in an event.
    ///
    /// - Parameters:
    ///   - event: The event whose p-tags identify recipient pubkeys.
    ///   - ndb: The local NostrDB instance to query for kind:10002 relay lists.
    ///   - excludeRelays: Relays already targeted (e.g. the author's own relays), which should be excluded from the result.
    ///   - additionalRelayLists: Pre-fetched relay lists (e.g. from a network fetch) to supplement NDB lookups.
    ///     These take priority over NDB for the same pubkey.
    /// - Returns: An array of inbox relay URLs (up to `MAX_INBOX_RELAYS`), excluding any in `excludeRelays`.
    static func resolveInboxRelays(event: NostrEvent, ndb: Ndb, excludeRelays: Set<RelayURL>, additionalRelayLists: [Pubkey: NIP65.RelayList] = [:]) -> [RelayURL] {
        let authorPubkey = event.pubkey
        var inboxRelays = Set<RelayURL>()

        for taggedPubkey in event.referenced_pubkeys {
            // Skip if the author tagged themselves
            if taggedPubkey == authorPubkey {
                continue
            }

            // Prefer pre-fetched relay list, fall back to NDB lookup
            guard let relayList = additionalRelayLists[taggedPubkey] ?? lookupRelayList(ndb: ndb, pubkey: taggedPubkey) else {
                continue
            }

            for (url, item) in relayList.relays {
                if item.rwConfiguration.canRead {
                    inboxRelays.insert(url)
                }
            }
        }

        // Remove relays already in the author's set
        inboxRelays.subtract(excludeRelays)

        // Stochastic selection: shuffle and cap to distribute across relays over time
        return Array(inboxRelays.shuffled().prefix(Self.MAX_INBOX_RELAYS))
    }

    /// Look up a pubkey's kind:10002 relay list from local NDB.
    ///
    /// - Parameters:
    ///   - ndb: The NostrDB instance.
    ///   - pubkey: The pubkey whose relay list to look up.
    /// - Returns: The parsed relay list, or `nil` if not found or unparseable.
    static func lookupRelayList(ndb: Ndb, pubkey: Pubkey) -> NIP65.RelayList? {
        guard let note = lookupRelayListEvent(ndb: ndb, pubkey: pubkey) else { return nil }
        return try? NIP65.RelayList(event: note)
    }

    /// Returns pubkeys p-tagged in the event that do NOT have a kind:10002 relay list in NDB.
    ///
    /// The author's own pubkey is always excluded from the result.
    ///
    /// - Parameters:
    ///   - event: The event whose p-tags identify recipient pubkeys.
    ///   - ndb: The local NostrDB instance to check for existing relay lists.
    /// - Returns: An array of pubkeys whose relay lists are missing from NDB.
    static func pubkeysMissingRelayLists(event: NostrEvent, ndb: Ndb) -> [Pubkey] {
        let authorPubkey = event.pubkey
        var missing: [Pubkey] = []

        for taggedPubkey in event.referenced_pubkeys {
            if taggedPubkey == authorPubkey {
                continue
            }
            if lookupRelayListEvent(ndb: ndb, pubkey: taggedPubkey) == nil {
                missing.append(taggedPubkey)
            }
        }

        return missing
    }

    /// Look up a pubkey's kind:10002 relay list event (already signed) from local NDB.
    ///
    /// - Parameters:
    ///   - ndb: The NostrDB instance.
    ///   - pubkey: The pubkey whose relay list event to look up.
    /// - Returns: The raw NdbNote event, or `nil` if not found.
    static func lookupRelayListEvent(ndb: Ndb, pubkey: Pubkey) -> NdbNote? {
        let filter = NostrFilter(kinds: [.relay_list], authors: [pubkey])
        guard let ndbFilter = try? NdbFilter(from: filter) else { return nil }
        guard let noteKeys = try? ndb.query(filters: [ndbFilter], maxResults: 1) else { return nil }
        guard let noteKey = noteKeys.first else { return nil }
        return try? ndb.lookup_note_by_key_and_copy(noteKey)
    }
}
