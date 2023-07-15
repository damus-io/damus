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
    @ObservedObject private var model_cache: RelayModelCache
    
    @Binding var showActionButtons: Bool
    
    init(state: DamusState, relay: String, showActionButtons: Binding<Bool>) {
        self.state = state
        self.relay = relay
        self.model_cache = state.relay_model_cache
        _showActionButtons = showActionButtons
    }
    
    var body: some View {
        Group {
            HStack {
                if let privkey = state.keypair.privkey {
                    if showActionButtons {
                        RemoveButton(privkey: privkey, showText: false)
                    }
                    else if let relay_connection {
                        RelayStatusView(connection: relay_connection)
                    }
                }
                
                RelayType(is_paid: state.relay_model_cache.model(with_relay_id: relay)?.metadata.is_paid ?? false)
                
                if let meta = model_cache.model(with_relay_id: relay)?.metadata {
                    Text(relay)
                        .background(
                            NavigationLink(value: Route.RelayDetail(relay: relay, metadata: meta), label: {
                                EmptyView()
                            }).opacity(0.0).disabled(showActionButtons)
                        )
                    
                    Spacer()

                    Image("info")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(Color.accentColor)
                } else {
                    Text(relay)
                    
                    Spacer()
                    
                    Image("question")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.gray)
                }
            }
        }
        .swipeActions {
            if let privkey = state.keypair.privkey {
                RemoveButton(privkey: privkey, showText: false)
                    .tint(.red)
            }
        }
        .contextMenu {
            CopyAction(relay: relay)
            
            if let privkey = state.keypair.privkey {
                RemoveButton(privkey: privkey, showText: true)
            }
        }
    }
    
    private var relay_connection: RelayConnection? {
        state.pool.get_relay(relay)?.connection
    }
    
    func CopyAction(relay: String) -> some View {
        Button {
            UIPasteboard.general.setValue(relay, forPasteboardType: "public.plain-text")
        } label: {
            Label(NSLocalizedString("Copy", comment: "Button to copy a relay server address."), image: "copy2")
        }
    }
        
    func RemoveButton(privkey: String, showText: Bool) -> some View {
        Button(action: {
            guard let ev = state.contacts.event else {
                return
            }
            
            let descriptors = state.pool.our_descriptors
            guard let new_ev = remove_relay( ev: ev, current_relays: descriptors, privkey: privkey, relay: relay) else {
                return
            }
            
            process_contact_event(state: state, ev: new_ev)
            state.postbox.send(new_ev)
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
        RelayView(state: test_damus_state(), relay: "wss://relay.damus.io", showActionButtons: .constant(false))
    }
}
