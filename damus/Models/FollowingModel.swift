//
//  FollowingModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation

class FollowingModel {
    let damus_state: DamusState
    var needs_sub: Bool = true
    
    let contacts: [Pubkey]
    let hashtags: [Hashtag]

    let sub_id: String = UUID().description
    
    init(damus_state: DamusState, contacts: [Pubkey], hashtags: [Hashtag]) {
        self.damus_state = damus_state
        self.contacts = contacts
        self.hashtags = hashtags
    }
    
    func get_filter<Y>(txn: NdbTxn<Y>) -> NostrFilter {
        var f = NostrFilter(kinds: [.metadata])
        f.authors = self.contacts.reduce(into: Array<Pubkey>()) { acc, pk in
            // don't fetch profiles we already have
            if damus_state.profiles.has_fresh_profile(id: pk, txn: txn) {
                return
            }
            acc.append(pk)
        }
        return f
    }
    
    func subscribe<Y>(txn: NdbTxn<Y>) {
        let filter = get_filter(txn: txn)
        if (filter.authors?.count ?? 0) == 0 {
            needs_sub = false
            return
        }
        let filters = [filter]
        //print_filters(relay_id: "following", filters: [filters])
        self.damus_state.pool.subscribe(sub_id: sub_id, filters: filters, handler: handle_event)
    }
    
    func unsubscribe() {
        if !needs_sub {
            return
        }
        print("unsubscribing from following \(sub_id)")
        self.damus_state.pool.unsubscribe(sub_id: sub_id)
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        // don't need to do anything here really
    }
}
