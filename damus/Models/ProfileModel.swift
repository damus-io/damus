//
//  ProfileModel.swift
//  damus
//
//  Created by William Casarin on 2022-04-27.
//

import Foundation

class ProfileModel: ObservableObject {
    @Published var events: [NostrEvent] = []
    let pubkey: String
    let damus: DamusState
    
    var seen_event: Set<String> = Set()
    var sub_id = UUID().description
    
    init(pubkey: String, damus: DamusState) {
        self.pubkey = pubkey
        self.damus = damus
    }
    
    func unsubscribe() {
        print("unsubscribing from profile \(pubkey) with sub_id \(sub_id)")
        damus.pool.unsubscribe(sub_id: sub_id)
    }
    
    func subscribe() {
        let kinds: [Int] = [
            NostrKind.text.rawValue,
            NostrKind.delete.rawValue,
            NostrKind.contacts.rawValue,
            NostrKind.metadata.rawValue,
            NostrKind.boost.rawValue
        ]
        
        var filter = NostrFilter.filter_authors([pubkey])
        filter.kinds = kinds
        filter.limit = 500
        
        print("subscribing to profile \(pubkey) with sub_id \(sub_id)")
        damus.pool.subscribe(sub_id: sub_id, filters: [filter], handler: handle_event)
    }
    
    func add_event(_ ev: NostrEvent) {
        if seen_event.contains(ev.id) {
            return
        }
        if ev.kind == 1 {
            self.events.append(ev)
            self.events = self.events.sorted { $0.created_at > $1.created_at }
        }
        seen_event.insert(ev.id)
    }
    
    private func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event:
            return
        case .nostr_event(let resp):
            switch resp {
            case .event(let sid, let ev):
                if sid != self.sub_id {
                    return
                }
                add_event(ev)
            case .notice(let notice):
                notify(.notice, notice)
            }
        }
    }
}
