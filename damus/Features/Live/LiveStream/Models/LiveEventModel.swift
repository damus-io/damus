//
//  LiveEventModel.swift
//  damus
//
//  Created by eric on 7/25/25.
//

import Foundation

/// The data model for the LiveEventHome view
class LiveEventModel: ObservableObject {
    var events: EventHolder
    @Published var loading: Bool = false
    
    let damus_state: DamusState
    let live_event_subid = UUID().description
    var seen_dtag: Set<String> = Set()
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
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

        var live_event_filter = NostrFilter(kinds: [.live])
        live_event_filter.until = UInt32(Date.now.timeIntervalSince1970)
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date())!
        live_event_filter.since = UInt32(twoWeeksAgo.timeIntervalSince1970)
        
        damus_state.nostrNetwork.pool.subscribe(sub_id: live_event_subid, filters: [live_event_filter], handler: handle_event, to: to_relays)
    }

    func unsubscribe(to: RelayURL? = nil) {
        loading = false
        damus_state.nostrNetwork.pool.unsubscribe(sub_id: live_event_subid)
    }

    func handle_event(relay_id: RelayURL, conn_ev: NostrConnectionEvent) {
        guard case .nostr_event(let event) = conn_ev else {
            return
        }
        
        switch event {
        case .event(let sub_id, let ev):
            guard sub_id == self.live_event_subid else {
                return
            }
            if ev.is_textlike && should_show_event(state: damus_state, ev: ev) && !ev.is_reply()
            {
                for tag in ev.tags {
                    guard tag.count >= 2 else { continue }
                    if tag[0].string() == "d" {
                        if seen_dtag.contains(tag[1].string()) {
                            return
                        } else {
                            seen_dtag.insert(tag[1].string())
                        }
                    }
                }

                if self.events.insert(ev) {
                    self.objectWillChange.send()
                }
            }
        case .notice(let msg):
            print("live events notice: \(msg)")
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
