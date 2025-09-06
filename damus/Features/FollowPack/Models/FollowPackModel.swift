//
//  FollowPackModel.swift
//  damus
//
//  Created by eric on 6/5/25.
//

import Foundation


class FollowPackModel: ObservableObject {
    var events: EventHolder
    @Published var loading: Bool = false
    
    let damus_state: DamusState
    var listener: Task<Void, Never>? = nil
    let limit: UInt32 = 500
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: damus_state, events: [ev])
        })
    }
    
    func subscribe(follow_pack_users: [Pubkey]) {
        loading = true
        self.listener?.cancel()
        self.listener = Task {
            await self.listenForUpdates(follow_pack_users: follow_pack_users)
        }
    }

    func unsubscribe(to: RelayURL? = nil) {
        loading = false
        self.listener?.cancel()
    }
    
    func listenForUpdates(follow_pack_users: [Pubkey]) async {
        let to_relays = damus_state.nostrNetwork.determineToRelays(filters: damus_state.relay_filters)
        var filter = NostrFilter(kinds: [.text, .chat])
        filter.until = UInt32(Date.now.timeIntervalSince1970)
        filter.authors = follow_pack_users
        filter.limit = 500
        
        for await item in damus_state.nostrNetwork.reader.subscribe(filters: [filter], to: to_relays) {
            switch item {
            case .event(borrow: let borrow):
                var event: NostrEvent? = nil
                try? borrow { ev in
                    event = ev.toOwned()
                }
                guard let event else { return }
                let should_show_event = await should_show_event(state: damus_state, ev: event)
                if event.is_textlike && should_show_event && !event.is_reply()
                {
                    if await self.events.insert(event) {
                        DispatchQueue.main.async {
                            self.objectWillChange.send()
                        }
                    }
                }
            case .eose:
                continue
            }
        }
    }
}

