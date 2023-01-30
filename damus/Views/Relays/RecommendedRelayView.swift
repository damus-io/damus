//
//  RecommendedRelayView.swift
//  damus
//
//  Created by William Casarin on 2022-12-29.
//

import SwiftUI

struct RecommendedRelayView: View {
    let damus: DamusState
    let relay: String
    let add_button: Bool
    
    init(damus: DamusState, relay: String) {
        self.damus = damus
        self.relay = relay
        self.add_button = true
    }
    
    init(damus: DamusState, relay: String, add_button: Bool) {
        self.damus = damus
        self.relay = relay
        self.add_button = add_button
    }
    
    var body: some View {
        HStack {
            Text(relay)
            Spacer()
            if add_button {
                if let privkey = damus.keypair.privkey {
                    Button(NSLocalizedString("Add", comment: "Button to add recommended relay server.")) {
                        guard let ev_before_add = damus.contacts.event else {
                            return
                        }
                        guard let ev_after_add = add_relay(ev: ev_before_add, privkey: privkey, current_relays: damus.pool.descriptors, relay: relay, info: .rw) else {
                            return
                        }
                        process_contact_event(pool: damus.pool, contacts: damus.contacts, pubkey: damus.pubkey, ev: ev_after_add)
                        damus.pool.send(.event(ev_after_add))
                    }
                }
            }
        }
    }
}

struct RecommendedRelayView_Previews: PreviewProvider {
    static var previews: some View {
        RecommendedRelayView(damus: test_damus_state(), relay: "wss://relay.damus.io")
    }
}
