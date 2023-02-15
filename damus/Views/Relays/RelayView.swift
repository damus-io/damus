//
//  RelayView.swift
//  damus
//
//  Created by William Casarin on 2022-10-16.
//

import SwiftUI

struct RelayView: View {
    let state: DamusState
    let relay: String
    
    var body: some View {
        Group {
            HStack {
                RelayStatus(pool: state.pool, relay: relay)
                RelayType(is_paid: state.relay_metadata.lookup(relay_id: relay)?.is_paid ?? false)
                if let meta = state.relay_metadata.lookup(relay_id: relay) {
                    NavigationLink {
                        RelayDetailView(state: state, relay: relay, nip11: meta)
                    } label: {
                        Text(relay)
                    }
                } else {
                    Text(relay)
                }
            }
        }
        .swipeActions {
            if let privkey = state.keypair.privkey {
                RemoveAction(privkey: privkey)
            }
        }
        .contextMenu {
            CopyAction(relay: relay)
            
            if let privkey = state.keypair.privkey {
                RemoveAction(privkey: privkey)
            }
        }
    }
    
    func CopyAction(relay: String) -> some View {
        Button {
            UIPasteboard.general.setValue(relay, forPasteboardType: "public.plain-text")
        } label: {
            Label(NSLocalizedString("Copy", comment: "Button to copy a relay server address."), systemImage: "doc.on.doc")
        }
    }
    
    func RemoveAction(privkey: String) -> some View {
        Button {
            guard let ev = state.contacts.event else {
                return
            }
            
            let descriptors = state.pool.descriptors
            guard let new_ev = remove_relay( ev: ev, current_relays: descriptors, privkey: privkey, relay: relay) else {
                return
            }
            
            process_contact_event(state: state, ev: new_ev)
            state.pool.send(.event(new_ev))
        } label: {
            Label(NSLocalizedString("Delete", comment: "Button to delete a relay server that the user connects to."), systemImage: "trash")
        }
        .tint(.red)
    }
}

struct RelayView_Previews: PreviewProvider {
    static var previews: some View {
        RelayView(state: test_damus_state(), relay: "wss://relay.damus.io")
    }
}
