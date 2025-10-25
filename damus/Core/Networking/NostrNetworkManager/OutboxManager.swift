//
//  OutboxManager.swift
//  damus
//
//  Created by OpenAI Codex on 2025-09-06.
//

import Combine
import Foundation
import os

/// Coordinates outbox-specific behaviour such as autopilot toggling and relay hint resolution.
final class OutboxManager {
    final class Telemetry: ObservableObject {
        @Published fileprivate(set) var fallbackCount: Int = 0
        @Published fileprivate(set) var lastRecoveredNoteId: NoteId?
    }
    
    private static let logger = Logger(
        subsystem: Constants.MAIN_APP_BUNDLE_IDENTIFIER,
        category: "outbox_manager"
    )
    
    private let relayPool: RelayPool
    private let hints: OutboxRelayHintProviding
    private(set) var isEnabled: Bool
    let telemetry: Telemetry
    
    init(
        relayPool: RelayPool,
        hints: OutboxRelayHintProviding,
        isEnabled: Bool = true
    ) {
        self.relayPool = relayPool
        self.hints = hints
        self.isEnabled = isEnabled
        self.telemetry = Telemetry()
    }
    
    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }
    
    /// Resolves a merged list of relay URLs that may contain the target authors represented by the filters.
    func relayURLs(for filters: [NostrFilter]) async -> [RelayURL] {
        guard isEnabled else { return [] }
        let authors = extractAuthors(from: filters)
        guard !authors.isEmpty else { return [] }
        
        let hintsByAuthor = await hints.relayURLs(for: authors)
        var merged: [RelayURL] = []
        var seen = Set<RelayURL>()
        
        for urls in hintsByAuthor.values {
            for url in urls where seen.insert(url).inserted {
                merged.append(url)
            }
        }
        
        return merged
    }
    
    /// Lets the manager cache freshly observed relay list events (useful when we already streamed the note elsewhere).
    func recordRelayListEvent(_ event: NdbNote) async {
        await hints.recordRelayListEvent(event)
    }
    
    /// Outbox relays use ephemeral pool descriptors so they do not mutate the user's saved list.
    func ensureEphemeralConnections(for relays: [RelayURL]) async {
        guard isEnabled else { return }
        for relay in relays {
            await addEphemeralRelayIfNeeded(relay)
        }
    }
    
    func recordFallback(noteId: NoteId) {
        DispatchQueue.main.async {
            self.telemetry.fallbackCount += 1
            self.telemetry.lastRecoveredNoteId = noteId
        }
    }
    
    private func extractAuthors(from filters: [NostrFilter]) -> [Pubkey] {
        var ordered: [Pubkey] = []
        var seen = Set<Pubkey>()
        
        for filter in filters {
            for author in (filter.authors ?? []) where seen.insert(author).inserted {
                ordered.append(author)
            }
        }
        
        return ordered
    }
    
    private func addEphemeralRelayIfNeeded(_ relayURL: RelayURL) async {
        do {
            if await relayPool.getRelay(relayURL) != nil { return }
            try await relayPool.add_ephemeral_relay(url: relayURL)
        } catch {
            Self.logger.error("Failed to ensure outbox relay \(relayURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension RelayPool {
    func getRelay(_ url: RelayURL) async -> Relay? {
        await MainActor.run {
            self.get_relay(url)
        }
    }
    
    func add_ephemeral_relay(url: RelayURL) async throws {
        let descriptor = RelayDescriptor(url: url, info: .read, variant: .ephemeral)
        try await add_relay(descriptor)
        await connect(to: [url])
    }
}
