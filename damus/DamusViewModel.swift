//
//  DamusViewModel.swift
//  damus
//
//  Created by Sam DuBois on 12/18/22.
//

import SwiftUI
import Starscream
import Kingfisher

/// Default relays to be used when setting up the user's account.
var BOOTSTRAP_RELAYS = [
    "wss://relay.damus.io",
    "wss://nostr-relay.wlvs.space",
    "wss://nostr.oxtr.dev",
]

class DamusViewModel: ObservableObject {
    
    // MARK: Constants and Variables
    
    let sub_id = UUID().description
    
    /// User Keypair object
    var keypair: Keypair
    
    var pubkey: String {
        return keypair.pubkey
    }
    
    var privkey: String? {
        return keypair.privkey
    }
    
    @Published var status: String = "Not connected"
    @Published var state: DamusState? = nil
    @Published var active_sheet: Sheets? = nil
    @Published var selected_timeline: Timeline? = .home
    @Published var is_thread_open: Bool = false
    @Published var is_profile_open: Bool = false
    @Published var event: NostrEvent? = nil
    @Published var active_profile: String? = nil
    @Published var active_search: NostrFilter? = nil
    @Published var active_event_id: String? = nil
    @Published var profile_open: Bool = false
    @Published var thread_open: Bool = false
    @Published var search_open: Bool = false
    @Published var filter_state: FilterState = .posts_and_replies
    @Published var home: HomeModel = HomeModel()
    
    // MARK: Initializer
    init(with key: Keypair) {
        self.keypair = key
    }
    
    // MARK: Functionality
    
    func switch_timeline(_ timeline: Timeline) {
        NotificationCenter.default.post(name: .switched_timeline, object: timeline)
        
        if timeline == self.selected_timeline {
            NotificationCenter.default.post(name: .scroll_to_top, object: nil)
            return
        }
        
        self.selected_timeline = timeline
        //NotificationCenter.default.post(name: .switched_timeline, object: timeline)
        //self.selected_timeline = timeline
    }
    
    func add_relay(_ pool: RelayPool, _ relay: String) {
        //add_rw_relay(pool, "wss://nostr-pub.wellorder.net")
        add_rw_relay(pool, relay)
        /*
        let profile = Profile(name: relay, about: nil, picture: nil)
        let ts = Int64(Date().timeIntervalSince1970)
        let tsprofile = TimestampedProfile(profile: profile, timestamp: ts)
        damus!.profiles.add(id: relay, profile: tsprofile)
         */
    }
    
    func connect() {
        let pool = RelayPool()
        
        for relay in BOOTSTRAP_RELAYS {
            add_relay(pool, relay)
        }
        
        pool.register_handler(sub_id: sub_id, handler: home.handle_event)

        self.state = DamusState(pool: pool, keypair: keypair,
                                likes: EventCounter(our_pubkey: pubkey),
                                boosts: EventCounter(our_pubkey: pubkey),
                                contacts: Contacts(),
                                tips: TipCounter(our_pubkey: pubkey),
                                profiles: Profiles(),
                                dms: home.dms
        )
        home.damus_state = self.state!
        
        pool.connect()
    }
    
}

struct TimestampedProfile {
    let profile: Profile
    let timestamp: Int64
}

enum Sheets: Identifiable {
    case post
    case reply(NostrEvent)

    var id: String {
        switch self {
        case .post: return "post"
        case .reply(let ev): return "reply-" + ev.id
        }
    }
}

enum ThreadState {
    case event_details
    case chatroom
}

enum FilterState : Int {
    case posts_and_replies = 1
    case posts = 0
}

func ws_nostr_event(relay: String, ev: WebSocketEvent) -> NostrEvent? {
    switch ev {
    case .binary(let dat):
        return NostrEvent(content: "binary data? \(dat.count) bytes", pubkey: relay)
    case .cancelled:
        return NostrEvent(content: "cancelled", pubkey: relay)
    case .connected:
        return NostrEvent(content: "connected", pubkey: relay)
    case .disconnected:
        return NostrEvent(content: "disconnected", pubkey: relay)
    case .error(let err):
        return NostrEvent(content: "error \(err.debugDescription)", pubkey: relay)
    case .text(let txt):
        return NostrEvent(content: "text \(txt)", pubkey: relay)
    case .pong:
        return NostrEvent(content: "pong", pubkey: relay)
    case .ping:
        return NostrEvent(content: "ping", pubkey: relay)
    case .viabilityChanged(let b):
        return NostrEvent(content: "viabilityChanged \(b)", pubkey: relay)
    case .reconnectSuggested(let b):
        return NostrEvent(content: "reconnectSuggested \(b)", pubkey: relay)
    }
}

struct LastNotification {
    let id: String
    let created_at: Int64
}
