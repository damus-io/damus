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
    
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    @State var conn_color: Color = .gray
    
    func update_connection_color() {
        for relay in state.pool.relays {
            if relay.id == self.relay {
                let c = relay.connection
                if c.isConnected {
                    conn_color = .green
                } else if c.isConnecting || c.isReconnecting {
                    conn_color = .yellow
                } else {
                    conn_color = .red
                }
            }
        }
    }
    
    var body: some View {
        HStack {
            Circle()
                .frame(width: 8.0, height: 8.0)
                .foregroundColor(conn_color)
            Text(relay)
        }
        .onReceive(timer) { _ in
            update_connection_color()
        }
        .onAppear() {
            update_connection_color()
        }
        .swipeActions {
            if let privkey = state.keypair.privkey {
                RemoveAction(privkey: privkey)
            }
        }
        .contextMenu {
            if let privkey = state.keypair.privkey {
                RemoveAction(privkey: privkey)
            }
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
            
            process_contact_event(pool: state.pool, contacts: state.contacts, pubkey: state.pubkey, ev: new_ev)
            state.pool.send(.event(new_ev))
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(.red)
    }
    
}

fileprivate func remove_action() {
    
}

struct RelayView_Previews: PreviewProvider {
    static var previews: some View {
        RelayView(state: test_damus_state(), relay: "wss://relay.damus.io", conn_color: .red)
    }
}
