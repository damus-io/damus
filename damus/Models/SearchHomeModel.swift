//
//  SearchHomeModel.swift
//  damus
//
//  Created by William Casarin on 2022-06-06.
//

import Foundation


/// The data model for the SearchHome view, typically something global-like
class SearchHomeModel: ObservableObject {
    @Published var events: [NostrEvent] = []
    let pool: RelayPool
    let sub_id = UUID().description
    let limit: UInt32 = 1000
    
    init(pool: RelayPool) {
        self.pool = pool
    }
    
    func get_base_filter() -> NostrFilter {
        var filter = NostrFilter.filter_text
        filter.limit = self.limit
        filter.until = Int64(Date.now.timeIntervalSince1970)
        return filter
    }
    
    func subscribe() {
        pool.subscribe(sub_id: sub_id, filters: [get_base_filter()], handler: handle_event)
    }

    func unsubscribe() {
        pool.unsubscribe(sub_id: sub_id)
    }
    
    func handle_event(relay_id: String, conn_ev: NostrConnectionEvent) {
        switch conn_ev {
        case .ws_event:
            break
        case .nostr_event(let event):
            switch event {
            case .event(let sub_id, let ev):
                guard sub_id == self.sub_id else {
                    return
                }
                guard self.events.count <= limit else {
                    return
                }
                if ev.kind == NostrKind.text.rawValue {
                    let _ = insert_uniq_sorted_event(events: &events, new_ev: ev) {
                        $0.created_at > $1.created_at
                    }
                }
            case .notice(let msg):
                print("search home notice: \(msg)")
            }
        }
    }
}
