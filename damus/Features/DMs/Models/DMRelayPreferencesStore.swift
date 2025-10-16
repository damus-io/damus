//
//  DMRelayPreferencesStore.swift
//  damus
//
//  Created by OpenAI Codex on 2025-02-14.
//

import Foundation
import Combine

final class DMRelayPreferencesStore: ObservableObject {
    @Published private(set) var preferences: [Pubkey: [RelayURL]]
    private var latestTimestamp: [Pubkey: UInt32]
    private var requested: Set<Pubkey>

    init(preferences: [Pubkey: [RelayURL]] = [:], latestTimestamp: [Pubkey: UInt32] = [:], requested: Set<Pubkey> = []) {
        self.preferences = preferences
        self.latestTimestamp = latestTimestamp
        self.requested = requested
    }

    func update(from event: NostrEvent) {
        guard event.kind == NostrKind.dmRelayPreferences.rawValue else {
            return
        }

        if let current = latestTimestamp[event.pubkey], current > event.created_at {
            return
        }

        let relays = event.tags.compactMap { tag -> RelayURL? in
            let strings = tag.strings()
            guard strings.count >= 2,
                  strings[0] == "relay",
                  let relay = RelayURL(strings[1]) else {
                return nil
            }
            return relay
        }

        preferences[event.pubkey] = Array(Set(relays))
        latestTimestamp[event.pubkey] = event.created_at
        requested.remove(event.pubkey)
    }

    func relays(for pubkey: Pubkey) -> [RelayURL]? {
        preferences[pubkey]
    }

    func shouldRequest(for pubkey: Pubkey) -> Bool {
        if preferences[pubkey] != nil {
            return false
        }

        if requested.contains(pubkey) {
            return false
        }

        requested.insert(pubkey)
        return true
    }
}
