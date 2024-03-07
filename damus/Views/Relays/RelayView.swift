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
    let recommended: Bool
    @ObservedObject private var model_cache: RelayModelCache
    
    @State var relay_state: Bool
    @Binding var showActionButtons: Bool
    
    init(state: DamusState, relay: String, showActionButtons: Binding<Bool>, recommended: Bool) {
        self.state = state
        self.relay = relay
        self.recommended = recommended
        self.model_cache = state.relay_model_cache
        _showActionButtons = showActionButtons
        let relay_state = RelayView.get_relay_state(pool: state.pool, relay: relay)
        self._relay_state = State(initialValue: relay_state)
    }
    
    static func get_relay_state(pool: RelayPool, relay: String) -> Bool {
        return pool.get_relay(relay) == nil
    }
    
    var body: some View {
        Group {
            HStack {
                if let privkey = state.keypair.privkey {
                    if showActionButtons && !recommended {
                        RemoveButton(privkey: privkey, showText: false)
                    }
                }

                let meta = model_cache.model(with_relay_id: relay)?.metadata
            
                RelayPicView(relay: relay, icon: meta?.icon, size: 55, highlight: .none, disable_animation: false)
                    
                VStack(alignment: .leading) {
                    HStack {
                        Text(meta?.name ?? relay)
                            .font(.headline)
                            .padding(.bottom, 2)
                            .lineLimit(1)
                        RelayType(is_paid: state.relay_model_cache.model(with_relay_id: relay)?.metadata.is_paid ?? false)
                    }
                    Text(relay)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .contextMenu {
                            CopyAction(relay: relay)
                            
                            if let privkey = state.keypair.privkey {
                                RemoveButton(privkey: privkey, showText: true)
                            }
                        }
                }
                    
                Spacer()
                
                if recommended {
                    if let keypair = state.keypair.to_full() {
                        VStack(alignment: .center) {
                            if relay_state {
                                AddButton(keypair: keypair)
                            } else {
                                Button(action: {
                                    remove_action(privkey: keypair.privkey)
                                }) {
                                    Text(NSLocalizedString("Added", comment: "Button to show relay server is already added to list."))
                                        .font(.caption)
                                }
                                .buttonStyle(NeutralButtonShape.capsule.style)
                                .opacity(0.5)
                            }
                        }
                        .padding(.horizontal, 5)
                    }
                } else {
                    if let relay_connection {
                        RelayStatusView(connection: relay_connection)
                    }
                    
                    Image("chevron-large-right")
                        .resizable()
                        .frame(width: 15, height: 15)
                        .foregroundColor(.gray)
                }
            }
            .contentShape(Rectangle())
        }
        .onReceive(handle_notify(.relays_changed)) { _ in
            self.relay_state = RelayView.get_relay_state(pool: state.pool, relay: self.relay)
        }
        .onTapGesture {
            state.nav.push(route: Route.RelayDetail(relay: relay, metadata: model_cache.model(with_relay_id: relay)?.metadata))
        }
    }
    
    private var relay_connection: RelayConnection? {
        state.pool.get_relay(relay)?.connection
    }
    
    func add_action(keypair: FullKeypair) {
        guard let ev_before_add = state.contacts.event else {
            return
        }
        guard let relay_url = RelayURL(relay),
            let ev_after_add = add_relay(ev: ev_before_add, keypair: keypair, current_relays: state.pool.our_descriptors, relay: relay_url, info: .rw) else {
            return
        }
        process_contact_event(state: state, ev: ev_after_add)
        state.postbox.send(ev_after_add)
        
        if let relay_metadata = make_relay_metadata(relays: state.pool.our_descriptors, keypair: keypair) {
            state.postbox.send(relay_metadata)
        }
    }
    
    func remove_action(privkey: Privkey) {
        guard let ev = state.contacts.event else {
            return
        }
        
        let descriptors = state.pool.our_descriptors
        guard let keypair = state.keypair.to_full(),
              let relay_url = RelayURL(relay),
              let new_ev = remove_relay(ev: ev, current_relays: descriptors, keypair: keypair, relay: relay_url) else {
            return
        }
        
        process_contact_event(state: state, ev: new_ev)
        state.postbox.send(new_ev)
        
        if let relay_metadata = make_relay_metadata(relays: state.pool.our_descriptors, keypair: keypair) {
            state.postbox.send(relay_metadata)
        }
    }
    
    func AddButton(keypair: FullKeypair) -> some View {
        Button(action: {
            add_action(keypair: keypair)
        }) {
            Text(NSLocalizedString("Add", comment: "Button to add relay server to list."))
                .font(.caption)
        }
        .buttonStyle(NeutralButtonShape.capsule.style)
    }
    
    func CopyAction(relay: String) -> some View {
        Button {
            UIPasteboard.general.setValue(relay, forPasteboardType: "public.plain-text")
        } label: {
            Label(NSLocalizedString("Copy", comment: "Button to copy a relay server address."), image: "copy2")
        }
    }
        
    func RemoveButton(privkey: Privkey, showText: Bool) -> some View {
        Button(action: {
            remove_action(privkey: privkey)
        }) {
            if showText {
                Text(NSLocalizedString("Disconnect", comment: "Button to disconnect from a relay server."))
            }
            
            Image("minus-circle")
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundColor(.red)
                .padding(.leading, 5)
        }
    }
}

struct RelayView_Previews: PreviewProvider {
    static var previews: some View {
        RelayView(state: test_damus_state, relay: "wss://relay.damus.io", showActionButtons: .constant(false), recommended: false)
    }
}
