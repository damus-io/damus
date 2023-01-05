//
//  ConfigView.swift
//  damus
//
//  Created by William Casarin on 2022-06-09.
//
import AVFoundation
import SwiftUI
import Kingfisher

struct ConfigView: View {
    let state: DamusState
    @Environment(\.dismiss) var dismiss
    @State var show_add_relay: Bool = false
    @State var confirm_logout: Bool = false
    @State var new_relay: String = ""
    @State var show_privkey: Bool = false
    @State var privkey: String
    @State var privkey_copied: Bool = false
    @State var pubkey_copied: Bool = false
    @State var relays: [RelayDescriptor]
    @EnvironmentObject var user_settings: UserSettingsStore
    
    let generator = UIImpactFeedbackGenerator(style: .light)
    
    init(state: DamusState) {
        self.state = state
        _privkey = State(initialValue: self.state.keypair.privkey_bech32 ?? "")
        _relays = State(initialValue: state.pool.descriptors)
    }
    
    // TODO: (jb55) could be more general but not gonna worry about it atm
    func CopyButton(is_pk: Bool) -> some View {
        return Button(action: {
            UIPasteboard.general.string = is_pk ? self.state.keypair.pubkey_bech32 : self.privkey
            self.privkey_copied = !is_pk
            self.pubkey_copied = is_pk
            generator.impactOccurred()
        }) {
            let copied = is_pk ? self.pubkey_copied : self.privkey_copied
            Image(systemName: copied ? "checkmark.circle" : "doc.on.doc")
        }
    }
    
    var recommended: [RelayDescriptor] {
        let rs: [RelayDescriptor] = []
        return BOOTSTRAP_RELAYS.reduce(into: rs) { (xs, x) in
            if let _ = state.pool.get_relay(x) {
            } else {
                xs.append(RelayDescriptor(url: URL(string: x)!, info: .rw))
            }
        }
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            Form {
                Section {
                    List(Array(relays), id: \.url) { relay in
                        RelayView(state: state, relay: relay.url.absoluteString)
                    }
                } header: {
                    HStack {
                        Text("Relays")
                        Spacer()
                        Button(action: { show_add_relay = true }) {
                            Image(systemName: "plus")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                Section("Recommended Relays") {
                    List(recommended, id: \.url) { r in
                        RecommendedRelayView(damus: state, relay: r.url.absoluteString)
                    }
                }
                
                Section("Public Account ID") {
                    HStack {
                        Text(state.keypair.pubkey_bech32)
                        
                        CopyButton(is_pk: true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                
                if let sec = state.keypair.privkey_bech32 {
                    Section("Secret Account Login Key") {
                        HStack {
                            if show_privkey == false {
                                SecureField("PrivateKey", text: $privkey)
                                    .disabled(true)
                            } else {
                                Text(sec)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            
                            CopyButton(is_pk: false)
                        }
                        
                        Toggle("Show", isOn: $show_privkey)
                    }
                }
                
                Section("Wallet Selector") {
                    Toggle("Show wallet selector", isOn: $user_settings.show_wallet_selector).toggleStyle(.switch)
                    Picker("Select default wallet",
                           selection: $user_settings.default_wallet) {
                        ForEach(Wallet.allCases, id: \.self) { wallet in
                            Text(wallet.model.displayName)
                                .tag(wallet.model.tag)
                        }
                    }
                }
                
                Section("Clear Cache") {
                    Button("Clear") {
                        KingfisherManager.shared.cache.clearMemoryCache()
                        KingfisherManager.shared.cache.clearDiskCache()
                        KingfisherManager.shared.cache.cleanExpiredDiskCache()
                    }
                }
                
                Section("Reset") {
                    Button("Logout") {
                        confirm_logout = true
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Logout", isPresented: $confirm_logout) {
            Button("Cancel") {
                confirm_logout = false
            }
            Button("Logout") {
                notify(.logout, ())
            }
        } message: {
            Text("Make sure your nsec account key is saved before you logout or you will lose access to this account")
        }
        .sheet(isPresented: $show_add_relay) {
            AddRelayView(show_add_relay: $show_add_relay, relay: $new_relay) { m_relay in
                guard var relay = m_relay else {
                    return
                }
                
                if relay.starts(with: "wss://") == false {
                    relay = "wss://" + relay
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
                
                state.pool.connect(to: [relay])
                
                guard let new_ev = add_relay(ev: ev, privkey: privkey, current_relays: state.pool.descriptors, relay: relay, info: info) else {
                    return
                }
                
                process_contact_event(pool: state.pool, contacts: state.contacts, pubkey: state.pubkey, ev: ev)
                
                state.pool.send(.event(new_ev))
            }
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
        .onReceive(handle_notify(.relays_changed)) { _ in
            self.relays = state.pool.descriptors
        }
    }
}

struct ConfigView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ConfigView(state: test_damus_state())
        }
    }
}
