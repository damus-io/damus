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
    
    @Binding var showActionButtons: Bool
    
    init(damus: DamusState, relay: String, showActionButtons: Binding<Bool>) {
        self.damus = damus
        self.relay = relay
        self.add_button = true
        self._showActionButtons = showActionButtons
    }
    
    init(damus: DamusState, relay: String, add_button: Bool, showActionButtons: Binding<Bool>) {
        self.damus = damus
        self.relay = relay
        self.add_button = add_button
        self._showActionButtons = showActionButtons
    }
    
    var body: some View {
        ZStack {
            HStack {
                if let privkey = damus.keypair.privkey {
                    if showActionButtons && add_button {
                        AddButton(privkey: privkey, showText: false)
                    }
                }
                
                RelayType(is_paid: damus.relay_metadata.lookup(relay_id: relay)?.is_paid ?? false)
                
                Text(relay).layoutPriority(1)

                if let meta = damus.relay_metadata.lookup(relay_id: relay) {
                    NavigationLink ( destination:
                        RelayDetailView(state: damus, relay: relay, nip11: meta)
                    ){
                        EmptyView()
                    }
                    .opacity(0.0)
                    .disabled(showActionButtons)
                    
                    Spacer()
                    
                    Image(systemName: "info.circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color.accentColor)
                } else {
                    Spacer()

                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(.gray)
                }
            }
        }
        .swipeActions {
            if add_button {
                if let privkey = damus.keypair.privkey {
                    AddButton(privkey: privkey, showText: false)
                        .tint(.accentColor)
                }
            }
        }
        .contextMenu {
            CopyAction(relay: relay)
            
            if let privkey = damus.keypair.privkey {
                AddButton(privkey: privkey, showText: true)
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
    
    func AddButton(privkey: String, showText: Bool) -> some View {
        Button(action: {
            add_action(privkey: privkey)
        }) {
            if showText {
                Text(NSLocalizedString("Connect", comment: "Button to connect to recommended relay server."))
            }
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.accentColor)
                .padding(.leading, 5)
        }
    }
    
    func add_action(privkey: String) {
        guard let ev_before_add = damus.contacts.event else {
            return
        }
        guard let ev_after_add = add_relay(ev: ev_before_add, privkey: privkey, current_relays: damus.pool.descriptors, relay: relay, info: .rw) else {
            return
        }
        process_contact_event(state: damus, ev: ev_after_add)
        damus.postbox.send(ev_after_add)
    }
}

struct RecommendedRelayView_Previews: PreviewProvider {
    static var previews: some View {
        RecommendedRelayView(damus: test_damus_state(), relay: "wss://relay.damus.io", showActionButtons: .constant(false))
    }
}
