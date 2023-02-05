//
//  ConfigView.swift
//  damus
//
//  Created by William Casarin on 2022-06-09.
//
import AVFoundation
import Kingfisher
import SwiftUI

struct ConfigView: View {
    let state: DamusState
    @Environment(\.dismiss) var dismiss
    @State var confirm_logout: Bool = false
    @State var confirm_delete_account: Bool = false
    @State var show_privkey: Bool = false
    @State var show_libretranslate_api_key: Bool = false
    @State var privkey: String
    @State var privkey_copied: Bool = false
    @State var pubkey_copied: Bool = false
    @State var delete_text: String = ""
    
    @ObservedObject var settings: UserSettingsStore
    
    let generator = UIImpactFeedbackGenerator(style: .light)
    
    init(state: DamusState) {
        self.state = state
        _privkey = State(initialValue: self.state.keypair.privkey_bech32 ?? "")
        _settings = ObservedObject(initialValue: state.settings)
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

    var body: some View {
        ZStack(alignment: .leading) {
            Form {
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
                    Toggle(NSLocalizedString("Show wallet selector", comment: "Toggle to show or hide selection of wallet."), isOn: $settings.show_wallet_selector).toggleStyle(.switch)
                    Picker(NSLocalizedString("Select default wallet", comment: "Prompt selection of user's default wallet"),
                           selection: $settings.default_wallet) {
                        ForEach(Wallet.allCases, id: \.self) { wallet in
                            Text(wallet.model.displayName)
                                .tag(wallet.model.tag)
                        }
                    }
                }

                Section(NSLocalizedString("LibreTranslate Translations", comment: "Section title for selecting the server that hosts the LibreTranslate machine translation API.")) {
                    Picker(NSLocalizedString("Server", comment: "Prompt selection of LibreTranslate server to perform machine translations on notes"), selection: $settings.libretranslate_server) {
                        ForEach(LibreTranslateServer.allCases, id: \.self) { server in
                            Text(server.model.displayName)
                                .tag(server.model.tag)
                        }
                    }

                    if settings.libretranslate_server != .none {
                        TextField(NSLocalizedString("URL", comment: "Example URL to LibreTranslate server"), text: $settings.libretranslate_url)
                            .disableAutocorrection(true)
                            .disabled(settings.libretranslate_server != .custom)
                            .autocapitalization(UITextAutocapitalizationType.none)
                        HStack {
                            if show_libretranslate_api_key {
                                TextField(NSLocalizedString("API Key (optional)", comment: "Example URL to LibreTranslate server"), text: $settings.libretranslate_api_key)
                                    .disableAutocorrection(true)
                                    .autocapitalization(UITextAutocapitalizationType.none)
                                Button(NSLocalizedString("Hide API Key", comment: "Button to hide the LibreTranslate server API key.")) {
                                    show_libretranslate_api_key = false
                                }
                            } else {
                                SecureField(NSLocalizedString("API Key (optional)", comment: "Example URL to LibreTranslate server"), text: $settings.libretranslate_api_key)
                                    .disableAutocorrection(true)
                                    .autocapitalization(UITextAutocapitalizationType.none)
                                Button(NSLocalizedString("Show API Key", comment: "Button to hide the LibreTranslate server API key.")) {
                                    show_libretranslate_api_key = true
                                }
                            }
                        }
                    }
                }

                Section(NSLocalizedString("Left Handed", comment: "Moves the post button to the left side of the screen")) {
                    Toggle(NSLocalizedString("Left Handed", comment: "Moves the post button to the left side of the screen"), isOn: $settings.left_handed)
                        .toggleStyle(.switch)
                }

                Section(NSLocalizedString("Clear Cache", comment: "Section title for clearing cached data.")) {
                    Button(NSLocalizedString("Clear", comment: "Button for clearing cached data.")) {
                        KingfisherManager.shared.cache.clearMemoryCache()
                        KingfisherManager.shared.cache.clearDiskCache()
                        KingfisherManager.shared.cache.cleanExpiredDiskCache()
                    }
                }

                if state.is_privkey_user {
                    Section(NSLocalizedString("Delete", comment: "Section title for deleting the user")) {
                        Button(NSLocalizedString("Delete Account", comment: "Button to delete the user's account."), role: .destructive) {
                            confirm_delete_account = true
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Settings", comment: "Navigation title for Settings view."))
        .navigationBarTitleDisplayMode(.large)
        .alert(NSLocalizedString("Delete Account", comment: "Alert for deleting the users account."), isPresented: $confirm_delete_account) {
            TextField("Type DELETE to delete", text: $delete_text)
            Button(NSLocalizedString("Cancel", comment: "Cancel deleting the user."), role: .cancel) {
                confirm_delete_account = false
            }
            Button(NSLocalizedString("Delete", comment: "Button for deleting the users account."), role: .destructive) {
                guard let full_kp = state.keypair.to_full() else {
                    return
                }
                
                guard delete_text == "DELETE" else {
                    return
                }
                
                let ev = created_deleted_account_profile(keypair: full_kp)
                state.pool.send(.event(ev))
                notify(.logout, ())
            }
        }
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
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
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
