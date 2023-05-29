//
//  RelayConfigView.swift
//  damus
//
//  Created by William Casarin on 2023-01-30.
//

import SwiftUI

struct RelayConfigView: View {
    let state: DamusState
    
    @State var new_relay: String = ""
    @State var relays: [RelayDescriptor]
    @State private var showActionButtons = false
    
    @StateObject var profile: ProfileModel
    
    @Environment(\.dismiss) var dismiss
    
    init(state: DamusState, profile: ProfileModel) {
        self.state = state
        self._profile = StateObject(wrappedValue: profile)
        
        _relays = State(initialValue: state.pool.our_descriptors)
    }
    
    var body: some View {
        MainContent
        .onReceive(handle_notify(.relays_changed)) { _ in
            self.relays = state.pool.our_descriptors
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
    
    var MainContent: some View {
        Form {
            Section {
                AddRelayView(relay: $new_relay)
            } header: {
                HStack {
                    Text(NSLocalizedString("Connect To Relay", comment: "Label for section for adding a relay server."))
                        .font(.system(size: 18, weight: .heavy))
                        .padding(.bottom, 5)
                }
            } footer: {
                VStack {
                    HStack {
                        Spacer()
                        if(!new_relay.isEmpty) {
                            Button(NSLocalizedString("Cancel", comment: "Button to cancel out of view adding user inputted relay.")) {
                                new_relay = ""
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 80, height: 30)
                            .foregroundColor(.white)
                            .background(LINEAR_GRADIENT)
                            .clipShape(Capsule())
                            .padding(EdgeInsets(top: 15, leading: 0, bottom: 0, trailing: 0))
                            
                            Button(NSLocalizedString("Add", comment: "Button to confirm adding user inputted relay.")) {

                                if new_relay.starts(with: "wss://") == false && new_relay.starts(with: "ws://") == false {
                                    new_relay = "wss://" + new_relay
                                }
                                
                                if new_relay.hasSuffix("/") {
                                    new_relay.removeLast();
                                }
                                
                                guard let url = RelayURL(new_relay) else {
                                    return
                                }
                                
                                guard let ev = state.contacts.event else {
                                    return
                                }
                                
                                guard let privkey = state.keypair.privkey else {
                                    return
                                }
                                
                                let info = RelayInfo.rw
                                let descriptor = RelayDescriptor(url: url, info: info)
                                guard (try? state.pool.add_relay(descriptor)) != nil else {
                                    return
                                }
                                
                                state.pool.connect(to: [new_relay])
                                
                                guard let new_ev = add_relay(ev: ev, privkey: privkey, current_relays: state.pool.our_descriptors, relay: new_relay, info: info) else {
                                    return
                                }
                                
                                process_contact_event(state: state, ev: ev)
                                
                                state.pool.send(.event(new_ev))
                                
                                new_relay = ""
                                
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 80, height: 30)
                            .foregroundColor(.white)
                            .background(LINEAR_GRADIENT)
                            .clipShape(Capsule())
                            .padding(EdgeInsets(top: 15, leading: 0, bottom: 0, trailing: 0))
                        }
                    }
                }
            }
            
            Section {
                List(Array(relays), id: \.url) { relay in
                    RelayView(state: state, relay: relay.url.id, showActionButtons: $showActionButtons)
                }
            } header: {
                HStack {
                    Text(NSLocalizedString("Connected Relays", comment: "Section title for relay servers that are connected."))
                        .font(.system(size: 18, weight: .heavy))
                        .padding(.bottom, 5)
                }
            }
            
            Section {
                Text(NSLocalizedString("Recommended relays are determined by the relays the people you follow are also using. This helps you discover other relays that you might also want to use as well.", comment: "Section explanation for recommended relays."))
                if !profile.get_recommended_relays().isEmpty {
                    List(profile.get_recommended_relays(), id: \.0.url) { (relayDescriptor, count) in
                        RecommendedRelayView(damus: state, relay: "\(relayDescriptor.url.id) (\(count))", showActionButtons: $showActionButtons)
                    }
                } else {
                    Text(NSLocalizedString("No recommended relays found", comment: "Explains that no recommended relays were found"))
                }
            } header: {
                Text(NSLocalizedString("Recommended Relays", comment: "Section title for recommend relay servers that could be added as part of configuration"))
                    .font(.system(size: 18, weight: .heavy))
                    .padding(.bottom, 5)
            }
        }
        .navigationTitle(NSLocalizedString("Relays", comment: "Title of relays view"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if state.keypair.privkey != nil {
                if showActionButtons {
                    Button("Done") {
                        showActionButtons.toggle()
                    }
                } else {
                    Button("Edit") {
                        showActionButtons.toggle()
                    }
                }
            }
        }
    }
}

struct RelayConfigView_Previews: PreviewProvider {
    static var previews: some View {
        let test_state = test_damus_state()
        let profile = ProfileModel(pubkey: test_state.pubkey, damus: test_state)

        RelayConfigView(state: test_state, profile: profile)
    }
}
