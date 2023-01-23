//
//  RepostsModel.swift
//  damus
//
//  Created by Terry Yiu on 1/22/23.
//

import Foundation

class RepostsModel: ObservableObject {
    let state: DamusState
    let target: String
    let sub_id: String
    let profiles_id: String

    @Published var reposts: [NostrEvent]

    init (state: DamusState, target: String) {
        self.state = state
        self.target = target
        self.sub_id = UUID().description
        self.profiles_id = UUID().description
        self.reposts = []
    }

    func get_filter() -> NostrFilter {
        var filter = NostrFilter.filter_kinds([NostrKind.boost.rawValue])
        filter.referenced_ids = [target]
        filter.limit = 500
        return filter
    }

    func subscribe() {
        let filter = get_filter()
        let filters = [filter]
        self.state.pool.subscribe(sub_id: sub_id, filters: filters, handler: handle_nostr_event)
    }

    func unsubscribe() {
        self.state.pool.unsubscribe(sub_id: sub_id)
    }

    func handle_event(relay_id: String, ev: NostrEvent) {
        guard ev.kind == NostrKind.boost.rawValue else {
            return
        }

        guard let reposted_event = last_etag(tags: ev.tags) else {
            return
        }

        guard reposted_event == self.target else {
            return
        }

        if insert_uniq_sorted_event(events: &self.reposts, new_ev: ev, cmp: { a, b in a.created_at < b.created_at } ) {
            objectWillChange.send()
        }
    }

    func handle_nostr_event(relay_id: String, ev: NostrConnectionEvent) {
        guard case .nostr_event(let nev) = ev else {
            return
        }

        switch nev {
        case .event(_, let ev):
            handle_event(relay_id: relay_id, ev: ev)

        case .notice(_):
            break
        case .eose(_):
            load_profiles(profiles_subid: profiles_id, relay_id: relay_id, events: reposts, damus_state: state)
            break
        }
    }
}
