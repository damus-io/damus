//
//  LiveChatModel.swift
//  damus
//
//  Created by eric on 8/7/25.
//

import Foundation

/// The data model for the LiveEventHome view
class LiveChatModel: ObservableObject {
    var events: EventHolder
    @Published var loading: Bool = false

    let damus_state: DamusState
    let root: String
    let dtag: String
    var subscriptionTask: Task<Void, any Error>? = nil
    let limit: UInt32 = 1000

    init(damus_state: DamusState, root: String, dtag: String) {
        self.damus_state = damus_state
        self.root = root
        self.dtag = dtag
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: damus_state, events: [ev])
        })
    }

    @MainActor
    func filter_muted() {
        events.filter { should_show_event(state: damus_state, ev: $0) }
        self.objectWillChange.send()
    }
    
    @MainActor
    func set(loading: Bool) {
        self.loading = loading
    }

    func subscribe() {
        subscriptionTask?.cancel()
        
        subscriptionTask = Task {
            await set(loading: true)
            
            let live_chat_filter = NostrFilter(kinds: [.live_chat])
            
            let to_relays = await damus_state.nostrNetwork.ourRelayDescriptors
                .map { $0.url }
                .filter { !damus_state.relay_filters.is_filtered(timeline: .search, relay_id: $0) }
            
            for await item in damus_state.nostrNetwork.reader.advancedStream(filters: [live_chat_filter], to: to_relays) {
                switch item {
                case .event(let lender):
                    await lender.justUseACopy({ await handle_event(event: $0) })
                case .eose:
                    continue
                case .ndbEose:
                    await set(loading: false)
                case .networkEose:
                    continue
                }
            }
        }
    }

    @MainActor
    func unsubscribe(to: RelayURL? = nil) {
        set(loading: false)
        subscriptionTask?.cancel()
    }

    func handle_event(event: NostrEvent) async {
        for tag in event.tags {
            guard tag.count >= 2 else { continue }
            switch tag[0].string() {
            case "a":
                let atag = tag[1].string()
                let split = atag.split(separator: ":")
                if root != split[1] {
                    return
                }
                if dtag != split[2] {
                    return
                }
            default:
                break
            }
        }
        await MainActor.run {
            if should_show_event(state: damus_state, ev: event) {
                if self.events.insert(event) {
                    self.objectWillChange.send()
                }
            }
        }
    }
}
