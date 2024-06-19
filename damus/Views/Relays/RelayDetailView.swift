//
//  RelayDetailView.swift
//  damus
//
//  Created by Joel Klabo on 2/1/23.
//

import SwiftUI

struct RelayDetailView: View {
    let state: DamusState
    let relay: RelayURL
    let nip11: RelayMetadata?

    @ObservedObject var log: RelayLog

    @Environment(\.dismiss) var dismiss

    init(state: DamusState, relay: RelayURL, nip11: RelayMetadata?) {
        self.state = state
        self.relay = relay
        self.nip11 = nip11
        
        log = state.relay_model_cache.model(with_relay_id: relay)?.log ?? RelayLog()
    }
    
    func check_connection() -> Bool {
        for relay in state.pool.relays {
            if relay.id == self.relay {
                return true
            }
        }
        return false
    }

    func RemoveRelayButton(_ keypair: FullKeypair) -> some View {
        Button(action: {
            guard let ev = state.contacts.event else {
                return
            }

            let descriptors = state.pool.our_descriptors
            guard let new_ev = remove_relay( ev: ev, current_relays: descriptors, keypair: keypair, relay: relay) else {
                return
            }

            process_contact_event(state: state, ev: new_ev)
            state.postbox.send(new_ev)
            
            if let relay_metadata = make_relay_metadata(relays: state.pool.our_descriptors, keypair: keypair) {
                state.postbox.send(relay_metadata)
            }
            dismiss()
        }) {
            HStack {
                Text("Disconnect", comment: "Button to disconnect from the relay.")
                    .fontWeight(.semibold)
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(NeutralButtonShape.rounded.style)
    }
    
    func ConnectRelayButton(_ keypair: FullKeypair) -> some View {
        Button(action: {
            guard let ev_before_add = state.contacts.event else {
                return
            }
            guard let ev_after_add = add_relay(ev: ev_before_add, keypair: keypair, current_relays: state.pool.our_descriptors, relay: relay, info: .rw) else {
                return
            }
            process_contact_event(state: state, ev: ev_after_add)
            state.postbox.send(ev_after_add)

            if let relay_metadata = make_relay_metadata(relays: state.pool.our_descriptors, keypair: keypair) {
                state.postbox.send(relay_metadata)
            }
            dismiss()
        }) {
            HStack {
                Text("Connect", comment: "Button to connect to the relay.")
                    .fontWeight(.semibold)
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(NeutralButtonShape.rounded.style)
    }
    
    var RelayInfo: some View {
        ScrollView(.horizontal) {
            Group {
                HStack(spacing: 15) {
                    
                    RelayAdminDetail(state: state, nip11: nip11)
                    
                    Divider().frame(width: 1)
                    
                    RelaySoftwareDetail(nip11: nip11)
                    
                }
            }
        }
        .scrollIndicators(.hidden)
    }
    
    var RelayHeader: some View {
        HStack(alignment: .top, spacing: 15) {
            RelayPicView(relay: relay, icon: nip11?.icon, size: 90, highlight: .none, disable_animation: false)
            
            VStack(alignment: .leading) {
                Text(nip11?.name ?? relay.absoluteString)
                    .font(.title)
                    .fontWeight(.bold)
                    .lineLimit(1)
                
                Text(relay.absoluteString)
                    .font(.headline)
                    .fontWeight(.regular)
                    .foregroundColor(.gray)
                
                HStack {
                    if nip11?.is_paid ?? false {
                        RelayPaidDetail(payments_url: nip11?.payments_url, fees: nip11?.fees)
                    }
                    
                    if let authentication_state: RelayAuthenticationState = relay_object?.authentication_state,
                       authentication_state != .none {
                        RelayAuthenticationDetail(state: authentication_state)
                    }
                }
            }
        }
    }
    

    var body: some View {
        NavigationView {
            Group {
                ScrollView {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {

                        RelayHeader
                        
                        Divider()
                        
                        Text("Description", comment: "Description of the specific Nostr relay server.")
                            .font(.subheadline)
                            .foregroundColor(DamusColors.mediumGrey)

                        if let description = nip11?.description, !description.isEmpty {
                            Text(description)
                                .font(.subheadline)
                        } else {
                            Text("N/A", comment: "Text label indicating that there is no NIP-11 relay description information found. In English, N/A stands for not applicable.")
                                .font(.subheadline)
                        }

                        Divider()
                        
                        RelayInfo
                        
                        Divider()
                        
                        if let nip11 {
                            if let nips = nip11.supported_nips, nips.count > 0 {
                                RelayNipList(nips: nips)
                                Divider()
                            }
                        }
                        
                        if let keypair = state.keypair.to_full() {
                            if check_connection() {
                                RemoveRelayButton(keypair)
                                    .padding(.top)
                            } else {
                                ConnectRelayButton(keypair)
                                    .padding(.top)
                            }
                        }
                        
                        if state.settings.developer_mode {
                            Text("Relay Logs", comment: "Text label indicating that the text below it are developer mode logs.")
                                .padding(.top)
                            Divider()
                            Text(log.contents ?? NSLocalizedString("No logs to display", comment: "Label to indicate that there are no developer mode logs available to be displayed on the screen"))
                                .font(.system(size: 13))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .onReceive(handle_notify(.switched_timeline)) { notif in
            dismiss()
        }
        .navigationTitle(nip11?.name ?? relay.absoluteString)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
        .ignoresSafeArea(.all)
        .toolbar {
            if let relay_connection {
                RelayStatusView(connection: relay_connection)
            }
        }
    }

    private var relay_object: Relay? {
        state.pool.get_relay(relay)
    }

    private var relay_connection: RelayConnection? {
        relay_object?.connection
    }
}

struct RelayDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let admission = Admission(amount: 1000000, unit: "msats")
        let sub = Subscription(amount: 5000000, unit: "msats", period: 2592000)
        let pub = Publication(kinds: [4], amount: 100, unit: "msats")
        let fees = Fees(admission: [admission], subscription: [sub], publication: [pub])
        let metadata = RelayMetadata(name: "name", description: "Relay description", pubkey: test_pubkey, contact: "contact@mail.com", supported_nips: [1,2,3], software: "software", version: "version", limitation: Limitations.empty, payments_url: "https://jb55.com", icon: "", fees: fees)
        RelayDetailView(state: test_damus_state, relay: RelayURL("wss://relay.damus.io")!, nip11: metadata)
    }
}
