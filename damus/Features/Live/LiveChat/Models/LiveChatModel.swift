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
    let live_chat_subid = UUID().description
    let limit: UInt32 = 1000

    init(damus_state: DamusState, root: String, dtag: String) {
        self.damus_state = damus_state
        self.root = root
        self.dtag = dtag
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: damus_state, events: [ev])
        })
    }

    func filter_muted() {
        events.filter { should_show_event(state: damus_state, ev: $0) }
        self.objectWillChange.send()
    }

    func subscribe() {
        loading = true
        let to_relays = determine_to_relays(pool: damus_state.nostrNetwork.pool, filters: damus_state.relay_filters)

        let live_chat_filter = NostrFilter(kinds: [.live_chat])

        damus_state.nostrNetwork.pool.subscribe(sub_id: live_chat_subid, filters: [live_chat_filter], handler: handle_event, to: to_relays)
    }


    func unsubscribe(to: RelayURL? = nil) {
        loading = false
        damus_state.nostrNetwork.pool.unsubscribe(sub_id: live_chat_subid, to: to.map { [$0] })
    }

    func handle_event(relay_id: RelayURL, conn_ev: NostrConnectionEvent) {
        guard case .nostr_event(let event) = conn_ev else {
            return
        }

        switch event {
        case .event(let sub_id, let ev):
            guard sub_id == self.live_chat_subid else {
                return
            }
            for tag in ev.tags {
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
            if should_show_event(state: damus_state, ev: ev)
            {
                if self.events.insert(ev) {
                    self.objectWillChange.send()
                }
            }
        case .notice(let msg):
            print("live chat events notice: \(msg)")
        case .ok:
            break
        case .eose(let sub_id):
            loading = false
            break
        case .auth:
            break
        }
    }
}
