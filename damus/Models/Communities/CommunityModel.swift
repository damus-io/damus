//
//  CommunityModel.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-05-09.
//

import Combine
import SwiftUI

@MainActor
class CommunityModel: ObservableObject {
    let id: NIP73.ID.Value
    let damus: DamusState
    let events: EventHolder
    private(set) var loading: Bool
    private(set) var listener: Task<Void, any Error>?
    
    init(id: NIP73.ID.Value, damus: DamusState) {
        self.id = id
        self.damus = damus
        self.events = EventHolder()
        self.loading = false
        self.listener = nil
    }
    
    func load() {
        self.loading = true
        self.events.should_queue = false    // TODO: Refine this
        self.listener?.cancel()
        self.listener = Task {
            try await listen()
        }
    }
    
    func listen() async throws {
        let filter = NostrFilter(kinds: [.scoped_comment], root_i_tags: [self.id.value])
        for await item in self.damus.nostrNetwork.reader.subscribe(filters: [filter]) {
            switch item {
            case .event(borrow: let borrow):
                try? borrow { event in   // TODO: Handle errors?
                    events.insert(event.toOwned())  // TODO: Improve this?
                }
            case .eose:
                loading = false
            }
        }
    }
    
}
