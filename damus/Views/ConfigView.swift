//
//  ConfigView.swift
//  damus
//
//  Created by William Casarin on 2022-06-09.
//

import SwiftUI
import AVFoundation

struct ConfigView: View {
    let state: DamusState
    @Environment(\.dismiss) var dismiss
    @State var show_add_relay: Bool = false
    @State var confirm_logout: Bool = false
    @State var new_relay: String = ""
    
    func Relay(_ ev: NostrEvent, relay: String) -> some View {
        return Text(relay)
            .swipeActions {
                if let privkey = state.keypair.privkey {
                    Button {
                        guard let new_ev = remove_relay( ev: ev, privkey: privkey, relay: relay) else {
                            return
                        }
                        
                        state.contacts.event = new_ev
                        state.pool.send(.event(new_ev))
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            Form {
                if let ev = state.contacts.event {
                    Section("Relays") {
                        if let relays = decode_json_relays(ev.content) {
                            List(Array(relays.keys.sorted()), id: \.self) { relay in
                                Relay(ev, relay: relay)
                            }
                        }
                        
                    }
                }
                
                Section("Public Account ID") {
                    Text(state.keypair.pubkey_bech32)
                        .textSelection(.enabled)
                        .onTapGesture {
                            UIPasteboard.general.string = state.keypair.pubkey_bech32
                            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                        }
                }
                    
                if let sec = state.keypair.privkey_bech32 {
                    Section("Secret Account Login Key") {
                        Text(sec)
                            .textSelection(.enabled)
                            .onTapGesture {
                                UIPasteboard.general.string = sec
                                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                            }
                    }
                }
                    
                Section("Reset") {
                    Button("Logout") {
                        confirm_logout = true
                    }
                }
            }
            
            VStack {
                HStack {
                    Spacer()
                    
                    Button(action: { show_add_relay = true }) {
                        Label("", systemImage: "plus")
                            .foregroundColor(.accentColor)
                            .padding()
                    }
                }
                
                Spacer()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Logout", isPresented: $confirm_logout) {
            Button("Logout") {
                notify(.logout, ())
            }
            Button("Cancel") {
                confirm_logout = false
            }
        } message: {
            Text("Make sure your nsec account key is saved before you logout or you will lose access to this account")
        }
        .sheet(isPresented: $show_add_relay) {
            AddRelayView(show_add_relay: $show_add_relay, relay: $new_relay) { m_relay in
                
                guard let relay = m_relay else {
                    return
                }
                
                guard let url = URL(string: relay) else {
                    return
                }
                
                guard let ev = state.contacts.event else {
                    return
                }
                
                guard let privkey = state.keypair.privkey else {
                    return
                }

                let info = RelayInfo.rw
                
                guard (try? state.pool.add_relay(url, info: info)) != nil else {
                    return
                }
                
                state.pool.connect(to: [new_relay])
                
                guard let new_ev = add_relay(ev: ev, privkey: privkey, relay: new_relay, info: info) else {
                    return
                }
                
                state.contacts.event = new_ev
                state.pool.send(.event(new_ev))
            }
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
}

struct ConfigView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigView(state: test_damus_state())
    }
}
