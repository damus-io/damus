//
//  OutboxRelayHints.swift
//  damus
//
//  Created by OpenAI Codex on 2025-09-06.
//

import Foundation
import os

/// Provides relay hint information (read-capable relays per author) for the outbox model.
protocol OutboxRelayHintProviding: Sendable {
    /// Returns the best-effort relay lists for each requested pubkey.
    func relayURLs(for pubkeys: [Pubkey]) async -> [Pubkey: [RelayURL]]
    /// Records a newly seen relay list event, updating cached hints immediately.
    func recordRelayListEvent(_ event: NdbNote) async
    /// Invalidates cached hints for specific authors (or all when the array is empty).
    func invalidate(pubkeys: [Pubkey]) async
}

/// Gathers relay hints out of existing NostrDB data and keeps a short-lived cache.
actor OutboxRelayHints: OutboxRelayHintProviding {
    private struct CacheEntry {
        let relays: [RelayURL]
        let timestamp: Date
        
        func isFresh(ttl: TimeInterval, now: Date = .now) -> Bool {
            ttl <= 0 || now.timeIntervalSince(timestamp) < ttl
        }
    }
    
    private static let logger = Logger(
        subsystem: Constants.MAIN_APP_BUNDLE_IDENTIFIER,
        category: "outbox_relay_hints"
    )
    
    private let ndb: Ndb
    private var cache: [Pubkey: CacheEntry] = [:]
    private let cacheTTL: TimeInterval
    private let maxResultsToInspect: Int
    
    init(
        ndb: Ndb,
        cacheTTL: TimeInterval = 5 * 60,
        maxResultsToInspect: Int = 32
    ) {
        self.ndb = ndb
        self.cacheTTL = cacheTTL
        self.maxResultsToInspect = maxResultsToInspect
    }
    
    func relayURLs(for pubkeys: [Pubkey]) async -> [Pubkey: [RelayURL]] {
        var resolved: [Pubkey: [RelayURL]] = [:]
        for pubkey in Set(pubkeys) {
            if pubkey == .empty { continue }
            if let relays = await cachedOrLoad(pubkey: pubkey), !relays.isEmpty {
                resolved[pubkey] = relays
            }
        }
        return resolved
    }
    
    func recordRelayListEvent(_ event: NdbNote) async {
        guard event.kind == NostrKind.relay_list.rawValue else { return }
        guard let relays = relayURLs(from: event) else { return }
        cache[event.pubkey] = CacheEntry(relays: relays, timestamp: Date())
    }
    
    func invalidate(pubkeys: [Pubkey]) async {
        if pubkeys.isEmpty {
            cache.removeAll()
            return
        }
        for pubkey in pubkeys {
            cache[pubkey] = nil
        }
    }
    
    private func cachedOrLoad(pubkey: Pubkey) async -> [RelayURL]? {
        if let entry = cache[pubkey], entry.isFresh(ttl: cacheTTL) {
            return entry.relays
        }
        
        guard let fresh = loadFromDatabase(pubkey: pubkey) else { return nil }
        cache[pubkey] = CacheEntry(relays: fresh, timestamp: Date())
        return fresh
    }
    
    private func loadFromDatabase(pubkey: Pubkey) -> [RelayURL]? {
        guard !ndb.is_closed else {
            Self.logger.warning("Skipping relay hint lookup: NostrDB closed.")
            return nil
        }
        guard let txn = NdbTxn<Void>(ndb: ndb, name: "outbox_relay_hints_load") else {
            Self.logger.error("Unable to open NostrDB transaction while loading relay hints.")
            return nil
        }
        
        do {
            let filters = try [NostrFilter(kinds: [.relay_list], authors: [pubkey])]
                .toNdbFilters()
            let noteKeys = try ndb.query(with: txn, filters: filters, maxResults: maxResultsToInspect)
            guard !noteKeys.isEmpty else { return nil }
            
            var latestEvent: NdbNote? = nil
            var latestTimestamp: UInt32 = 0
            for noteKey in noteKeys {
                guard let note = ndb.lookup_note_by_key_with_txn(noteKey, txn: txn) else { continue }
                if note.created_at >= latestTimestamp {
                    latestTimestamp = note.created_at
                    latestEvent = note
                }
            }
            
            guard let latestEvent else { return nil }
            return relayURLs(from: latestEvent)
        } catch {
            Self.logger.error("Failed to read relay hints for \(pubkey.hex(), privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    private func relayURLs(from event: NdbNote) -> [RelayURL]? {
        guard let relayList = try? NIP65.RelayList(event: event) else {
            Self.logger.error("Failed to decode relay list for \(event.pubkey.hex(), privacy: .public)")
            return nil
        }
        
        var ordered: [RelayURL] = []
        var seen: Set<RelayURL> = []
        
        for item in relayList.relays.values where item.rwConfiguration.canRead {
            if seen.insert(item.url).inserted {
                ordered.append(item.url)
            }
        }
        
        return ordered
    }
}
