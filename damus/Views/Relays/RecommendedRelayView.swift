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
    let user_recommended: Bool
    
    @ObservedObject private var model_cache: RelayModelCache
    
    init(damus: DamusState, relay: String, add_button: Bool = true, user_recommended: Bool = false) {
        self.damus = damus
        self.relay = relay
        self.add_button = add_button
        self.user_recommended = user_recommended
        self.model_cache = damus.relay_model_cache
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
        let meta = model_cache.model(with_relay_id: relay)?.metadata
        
        if user_recommended {
            HStack {
                RelayPicView(relay: relay, icon: meta?.icon, size: 50, highlight: .none, disable_animation: false)
                    .padding(.horizontal, 5)
                
                VStack(alignment: .leading) {
                    HStack {
                        Text(meta?.name ?? relay)
                            .font(.headline)
                            .padding(.bottom, 2)
                        
                        RelayType(is_paid: damus.relay_model_cache.model(with_relay_id: relay)?.metadata.is_paid ?? false)
                    }
                    
                    Text(relay)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if let keypair = damus.keypair.to_full() {
                    VStack(alignment: .center) {
                        if damus.pool.get_relay(relay) == nil {
                            AddButton(keypair: keypair)
                        } else {
                            Image(systemName: "checkmark.circle")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .foregroundColor(DamusColors.success)
                                .padding(.trailing, 10)
                        }
                    }
                    .padding(.horizontal, 5)
                }
            }
        } else {
            VStack {
                RelayPicView(relay: relay, icon: meta?.icon, size: 70, highlight: .none, disable_animation: false)
                if let meta = damus.relay_model_cache.model(with_relay_id: relay)?.metadata {
                    NavigationLink(value: Route.RelayDetail(relay: relay, metadata: meta)){
                        EmptyView()
                    }
                    .opacity(0.0)
                }
                
                HStack {
                    Text(meta?.name ?? relay)
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
        guard let relay_url = RelayURL(relay),
            let ev_after_add = add_relay(ev: ev_before_add, keypair: keypair, current_relays: damus.pool.our_descriptors, relay: relay_url, info: .rw) else {
            return
        }
        process_contact_event(state: damus, ev: ev_after_add)
        damus.postbox.send(ev_after_add)
    }
}

struct RecommendedRelayView_Previews: PreviewProvider {
    static var previews: some View {
        RecommendedRelayView(damus: test_damus_state, relay: "wss://relay.damus.io", user_recommended: true)
    }
}
