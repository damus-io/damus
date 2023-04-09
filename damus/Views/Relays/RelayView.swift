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
    
    @Binding var showActionButtons: Bool
    
    var body: some View {
        Group {
            HStack {
                if let privkey = state.keypair.privkey {
                    if showActionButtons {
                        RemoveButton(privkey: privkey, showText: false)
                    }
                    else {
                        RelayStatus(pool: state.pool, relay: relay)
                    }
                }
                
                RelayType(is_paid: state.relay_metadata.lookup(relay_id: relay)?.is_paid ?? false)
                
                if let meta = state.relay_metadata.lookup(relay_id: relay) {
                    Text(relay)
                        .background(
                            NavigationLink("", destination: RelayDetailView(state: state, relay: relay, nip11: meta)).opacity(0.0)
                                .disabled(showActionButtons)
                        )
                    Spacer()

                    Image(systemName: "info.circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color.accentColor)
                } else {
                    Text(relay)
                    Spacer()
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 20, weight: .regular))
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
    
    func CopyAction(relay: String) -> some View {
        Button {
            UIPasteboard.general.setValue(relay, forPasteboardType: "public.plain-text")
        } label: {
            Label(NSLocalizedString("Copy", comment: "Button to copy a relay server address."), systemImage: "doc.on.doc")
        }
    }
        
    func RemoveButton(privkey: String, showText: Bool) -> some View {
        Button(action: {
            guard let ev = state.contacts.event else {
                return
            }
            
            let descriptors = state.pool.descriptors
            guard let new_ev = remove_relay( ev: ev, current_relays: descriptors, privkey: privkey, relay: relay) else {
                return
            }
            
            process_contact_event(state: state, ev: new_ev)
            state.postbox.send(new_ev)
        }) {
            if showText {
                Text(NSLocalizedString("Disconnect", comment: "Button to disconnect from a relay server."))
            }
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 20, weight: .medium))
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
