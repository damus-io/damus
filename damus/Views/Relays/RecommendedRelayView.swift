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
        ZStack {
            HStack {
                RelayType(is_paid: damus.relay_metadata.lookup(relay_id: relay)?.is_paid ?? false)
                Text(relay).layoutPriority(1)

                if let meta = damus.relay_metadata.lookup(relay_id: relay) {
                    NavigationLink ( destination:
                        RelayDetailView(state: damus, relay: relay, nip11: meta)
                    ){
                        EmptyView()
                    }
                    .opacity(0.0)
                    
                    Spacer()
                    Image(systemName: "info.circle")
                        .foregroundColor(Color.accentColor)
                }
            }
        }
        .swipeActions {
            if add_button {
                if let privkey = damus.keypair.privkey {
                    AddAction(privkey: privkey)
                }
            }
        }
    }
    
    func AddAction(privkey: String) -> some View {
        Button {
            guard let ev_before_add = damus.contacts.event else {
                return
            }
            guard let ev_after_add = add_relay(ev: ev_before_add, privkey: privkey, current_relays: damus.pool.descriptors, relay: relay, info: .rw) else {
                return
            }
            process_contact_event(state: damus, ev: ev_after_add)
            damus.pool.send(.event(ev_after_add))
        } label: {
            Label(NSLocalizedString("Add Relay", comment: "Button to add recommended relay server."), systemImage: "plus.circle")
        }
        .tint(.accentColor)
    }
}

struct RecommendedRelayView_Previews: PreviewProvider {
    static var previews: some View {
        RecommendedRelayView(damus: test_damus_state(), relay: "wss://relay.damus.io")
    }
}
