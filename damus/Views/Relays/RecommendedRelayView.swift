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
    
    @ObservedObject private var model_cache: RelayModelCache
    
    @Binding var showActionButtons: Bool
    
    init(damus: DamusState, relay: String, add_button: Bool = true, showActionButtons: Binding<Bool>) {
        self.damus = damus
        self.relay = relay
        self.add_button = add_button
        self.model_cache = damus.relay_model_cache
        self._showActionButtons = showActionButtons
    }
    
    var recommended: [RelayDescriptor] {
        let rs: [RelayDescriptor] = []
        return BOOTSTRAP_RELAYS.reduce(into: rs) { xs, x in
            if damus.pool.get_relay(x) == nil, let url = RelayURL(x) {
                xs.append(RelayDescriptor(url: url, info: .rw))
            }
        }
    }
    
    var body: some View {
        VStack {
            let meta = model_cache.model(with_relay_id: relay)?.metadata
            
            RelayPicView(relay: relay, icon: meta?.icon, size: 70, highlight: .none, disable_animation: false)
            if let meta = damus.relay_model_cache.model(with_relay_id: relay)?.metadata {
                NavigationLink(value: Route.RelayDetail(relay: relay, metadata: meta)){
                    EmptyView()
                }
                .opacity(0.0)
                .disabled(showActionButtons)
            }
            
            HStack {
                Text(meta?.name ?? relay.hostname ?? relay)
                    .lineLimit(1)
            }
            .contextMenu {
                CopyAction(relay: relay)
            }
            
            if let keypair = damus.keypair.to_full() {
                AddButton(keypair: keypair)
            }
        }
    }
    
    func CopyAction(relay: String) -> some View {
        Button {
            UIPasteboard.general.setValue(relay, forPasteboardType: "public.plain-text")
        } label: {
            Label(NSLocalizedString("Copy", comment: "Button to copy a relay server address."), image: "copy")
        }
    }
    
    func AddButton(keypair: FullKeypair) -> some View {
        Button(action: {
            add_action(keypair: keypair)
        }) {
            Text(NSLocalizedString("Add", comment: "Button to add relay server to list."))
                .padding(10)
        }
        .buttonStyle(NeutralButtonStyle())
    }
    
    func add_action(keypair: FullKeypair) {
        guard let ev_before_add = damus.contacts.event else {
            return
        }
        guard let ev_after_add = add_relay(ev: ev_before_add, keypair: keypair, current_relays: damus.pool.our_descriptors, relay: relay, info: .rw) else {
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
