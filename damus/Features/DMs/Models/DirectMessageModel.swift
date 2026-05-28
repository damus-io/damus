//
//  DirectMessageModel.swift
//  damus
//
//  Created by William Casarin on 2022-07-03.
//

import Foundation

class DirectMessageModel: ObservableObject {
    @Published var events: [NostrEvent] {
        didSet {
            is_request = determine_is_request()
        }
    }

    @Published var draft: String = ""

    /// True while the other participant is actively typing (best-effort, time-based).
    @Published private(set) var partner_is_typing: Bool = false
    private var typing_clear_work: DispatchWorkItem?
    
    let pubkey: Pubkey

    var is_request = false
    var our_pubkey: Pubkey

    func determine_is_request() -> Bool {
        for event in events {
            if event.pubkey == our_pubkey {
                return false
            }
        }
        
        return true
    }
    
    init(events: [NostrEvent] = [], our_pubkey: Pubkey, pubkey: Pubkey) {
        self.events = events
        self.our_pubkey = our_pubkey
        self.pubkey = pubkey
    }

    /// Update the local typing state for the DM partner.
    ///
    /// We automatically clear after a short timeout to avoid getting stuck "on"
    /// if we miss a stop event (ephemeral delivery is best-effort).
    @MainActor
    func set_partner_typing(_ isTyping: Bool, autoClearAfter seconds: TimeInterval = 8.0) {
        typing_clear_work?.cancel()
        typing_clear_work = nil

        partner_is_typing = isTyping

        guard isTyping else {
            return
        }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.partner_is_typing = false
            }
        }
        typing_clear_work = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
