//
//  FollowersModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-26.
//

import Foundation

class FollowersModel: ObservableObject {
    let damus_state: DamusState
    let target: Pubkey

    @Published var contacts: [Pubkey]? = nil
    var has_contact: Set<Pubkey> = Set()

    var listener: Task<Void, Never>? = nil
    var profilesListener: Task<Void, Never>? = nil
    
    var count: Int? {
        guard let contacts = self.contacts else {
            return nil
        }
        return contacts.count
    }
    
    init(damus_state: DamusState, target: Pubkey) {
        self.damus_state = damus_state
        self.target = target
    }
    
    func get_filter() -> NostrFilter {
        NostrFilter(kinds: [.contacts], pubkeys: [target])
    }
    
    func subscribe() {
        let filter = get_filter()
        let filters = [filter]
        self.listener?.cancel()
        self.listener = Task {
            for await lender in damus_state.nostrNetwork.reader.streamIndefinitely(filters: filters) {
                lender.justUseACopy({ self.handle_event(ev: $0) })
            }
        }
    }
    
    func unsubscribe() {
        self.listener?.cancel()
        self.profilesListener?.cancel()
        self.listener = nil
        self.profilesListener = nil
    }
    
    @MainActor
    func handle_contact_event(_ ev: NostrEvent) {
        if has_contact.contains(ev.pubkey) {
            return
        }
        process_contact_event(state: damus_state, ev: ev)
        contacts?.append(ev.pubkey)
        has_contact.insert(ev.pubkey)
    }
    
    func handle_event(ev: NostrEvent) {
        if ev.known_kind == .contacts {
            Task { await handle_contact_event(ev) }
        }
    }
}
