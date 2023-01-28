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
                        Text("Relays", comment: "Header text for relay server list for configuration.")
                        Spacer()
                        Button(action: { show_add_relay = true }) {
                            Image(systemName: "plus")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                if recommended.count > 0 {
                    Section(NSLocalizedString("Recommended Relays", comment: "Section title for recommend relay servers that could be added as part of configuration")) {
                        List(recommended, id: \.url) { r in
                            RecommendedRelayView(damus: state, relay: r.url.absoluteString)
                        }
                    }
                }
                
                Section(NSLocalizedString("Public Account ID", comment: "Section title for the user's public account ID.")) {
                    HStack {
                        Text(state.keypair.pubkey_bech32)
                        
                        CopyButton(is_pk: true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                
                if let sec = state.keypair.privkey_bech32 {
                    Section(NSLocalizedString("Secret Account Login Key", comment: "Section title for user's secret account login key.")) {
                        HStack {
                            if show_privkey == false {
                                SecureField(NSLocalizedString("Private Key", comment: "Title of the secure field that holds the user's private key."), text: $privkey)
                                    .disabled(true)
                            } else {
                                Text(sec)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            
                            CopyButton(is_pk: false)
                        }
                        
                        Toggle(NSLocalizedString("Show", comment: "Toggle to show or hide user's secret account login key."), isOn: $show_privkey)
                    }
                }
                
                Section(NSLocalizedString("Wallet Selector", comment: "Section title for selection of wallet.")) {
                    Toggle(NSLocalizedString("Show wallet selector", comment: "Toggle to show or hide selection of wallet."), isOn: $user_settings.show_wallet_selector).toggleStyle(.switch)
                    Picker(NSLocalizedString("Select default wallet", comment: "Prompt selection of user's default wallet"),
                           selection: $user_settings.default_wallet) {
                        ForEach(Wallet.allCases, id: \.self) { wallet in
                            Text(wallet.model.displayName)
                                .tag(wallet.model.tag)
                        }
                    }
                }

                Section(NSLocalizedString("Left Handed", comment: "Moves the post button to the left side of the screen")) {
                    Toggle(NSLocalizedString("Left Handed", comment: "Moves the post button to the left side of the screen"), isOn: $user_settings.left_handed)
                        .toggleStyle(.switch)
                }

                Section(NSLocalizedString("Clear Cache", comment: "Section title for clearing cached data.")) {
                    Button(NSLocalizedString("Clear", comment: "Button for clearing cached data.")) {
                        KingfisherManager.shared.cache.clearMemoryCache()
                        KingfisherManager.shared.cache.clearDiskCache()
                        KingfisherManager.shared.cache.cleanExpiredDiskCache()
                    }
                }

                Section(NSLocalizedString("Reset", comment: "Section title for resetting the user")) {
                    Button(NSLocalizedString("Logout", comment: "Button to logout the user.")) {
                        confirm_logout = true
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Settings", comment: "Navigation title for Settings view."))
        .navigationBarTitleDisplayMode(.large)
        .alert(NSLocalizedString("Logout", comment: "Alert for logging out the user."), isPresented: $confirm_logout) {
            Button(NSLocalizedString("Cancel", comment: "Cancel out of logging out the user."), role: .cancel) {
                confirm_logout = false
            }
            Button(NSLocalizedString("Logout", comment: "Button for logging out the user."), role: .destructive) {
                notify(.logout, ())
            }
        } message: {
                Text("Make sure your nsec account key is saved before you logout or you will lose access to this account", comment: "Reminder message in alert to get customer to verify that their private security account key is saved saved before logging out.")
        }
        .sheet(isPresented: $show_add_relay) {
            AddRelayView(show_add_relay: $show_add_relay, relay: $new_relay) { m_relay in
                guard var relay = m_relay else {
                    return
                }
                
                if relay.starts(with: "wss://") == false && relay.starts(with: "ws://") == false {
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
