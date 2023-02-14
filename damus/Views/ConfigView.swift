//
//  ConfigView.swift
//  damus
//
//  Created by William Casarin on 2022-06-09.
//
import AVFoundation
import Kingfisher
import SwiftUI
import LocalAuthentication
import Combine

struct ConfigView: View {
    let state: DamusState
    @Environment(\.dismiss) var dismiss
    @State var confirm_logout: Bool = false
    @State var confirm_delete_account: Bool = false
    @State var show_privkey: Bool = false
    @State var has_authenticated_locally: Bool = false
    @State var show_api_key: Bool = false
    @State var privkey: String
    @State var privkey_copied: Bool = false
    @State var pubkey_copied: Bool = false
    @State var delete_text: String = ""
    @State var default_zap_amount: String
    
    @ObservedObject var settings: UserSettingsStore
    
    let generator = UIImpactFeedbackGenerator(style: .light)
    
    init(state: DamusState) {
        self.state = state
        let zap_amt = get_default_zap_amount(pubkey: state.pubkey).map({ "\($0)" }) ?? "1000"
        _default_zap_amount = State(initialValue: zap_amt)
        _privkey = State(initialValue: self.state.keypair.privkey_bech32 ?? "")
        _settings = ObservedObject(initialValue: state.settings)
    }

    func authenticateLocally(completion: @escaping (Bool) -> Void) {
        // Need to authenticate only once while ConfigView is presented
        guard !has_authenticated_locally else {
            completion(true)
            return
        }
        let context = LAContext()
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: NSLocalizedString("Local authentication to access private key", comment: "Face ID usage description shown when trying to access private key")) { success, error in
                DispatchQueue.main.async {
                    has_authenticated_locally = success
                    completion(success)
                }
            }
        } else {
            // If there's no authentication set up on the device, let the user copy the key without it
            has_authenticated_locally = true
            completion(true)
        }
    }
    
    // TODO: (jb55) could be more general but not gonna worry about it atm
    func CopyButton(is_pk: Bool) -> some View {
        return Button(action: {
            let copyKey = {
                UIPasteboard.general.string = is_pk ? self.state.keypair.pubkey_bech32 : self.privkey
                self.privkey_copied = !is_pk
                self.pubkey_copied = is_pk
                generator.impactOccurred()
            }
            if has_authenticated_locally {
                copyKey()
            } else {
                authenticateLocally { success in
                    if success {
                        copyKey()
                    }
                }
            }
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
                            if show_privkey == false || !has_authenticated_locally {
                                SecureField(NSLocalizedString("Private Key", comment: "Title of the secure field that holds the user's private key."), text: $privkey)
                                    .disabled(true)
                            } else {
                                Text(sec)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }

                            CopyButton(is_pk: false)
                        }

                        Toggle(NSLocalizedString("Show", comment: "Toggle to show or hide user's secret account login key."), isOn: $show_privkey)
                            .onChange(of: show_privkey) { newValue in
                                if newValue {
                                    authenticateLocally { success in
                                        show_privkey = success
                                    }
                                }
                            }
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
                
                
                Section(NSLocalizedString("Default Zap Amount in sats", comment: "Section title for zap configuration")) {
                    TextField("1000", text: $default_zap_amount)
                        .keyboardType(.numberPad)
                        .onReceive(Just(default_zap_amount)) { newValue in
                            let filtered = newValue.filter { Set("0123456789").contains($0) }

                            if filtered != newValue {
                                default_zap_amount = filtered
                            }

                            if filtered == "" {
                                set_default_zap_amount(pubkey: state.pubkey, amount: 1000)
                                return
                            }

                            guard let amt = Int(filtered) else {
                                return
                            }
                            set_default_zap_amount(pubkey: state.pubkey, amount: amt)
                        }
                }

                Section(NSLocalizedString("Translations", comment: "Section title for selecting the translation service.")) {
                    Picker(NSLocalizedString("Service", comment: "Prompt selection of translation service provider."), selection: $settings.translation_service) {
                        ForEach(TranslationService.allCases, id: \.self) { server in
                            Text(server.model.displayName)
                                .tag(server.model.tag)
                        }
                    }

                    if settings.translation_service == .libretranslate {
                        Picker(NSLocalizedString("Server", comment: "Prompt selection of LibreTranslate server to perform machine translations on notes"), selection: $settings.libretranslate_server) {
                            ForEach(LibreTranslateServer.allCases, id: \.self) { server in
                                Text(server.model.displayName)
                                    .tag(server.model.tag)
                            }
                        }

                        if settings.libretranslate_server == .custom {
                            TextField(NSLocalizedString("URL", comment: "Example URL to LibreTranslate server"), text: $settings.libretranslate_url)
                                .disableAutocorrection(true)
                                .autocapitalization(UITextAutocapitalizationType.none)
                        }

                        SecureField(NSLocalizedString("API Key (optional)", comment: "Prompt for optional entry of API Key to use translation server."), text: $settings.libretranslate_api_key)
                            .disableAutocorrection(true)
                            .disabled(settings.translation_service != .libretranslate)
                            .autocapitalization(UITextAutocapitalizationType.none)
                    }

                    if settings.translation_service == .deepl {
                        Picker(NSLocalizedString("Plan", comment: "Prompt selection of DeepL subscription plan to perform machine translations on notes"), selection: $settings.deepl_plan) {
                            ForEach(DeepLPlan.allCases, id: \.self) { server in
                                Text(server.model.displayName)
                                    .tag(server.model.tag)
                            }
                        }

                        SecureField(NSLocalizedString("API Key (required)", comment: "Prompt for required entry of API Key to use translation server."), text: $settings.deepl_api_key)
                            .disableAutocorrection(true)
                            .disabled(settings.translation_service != .deepl)
                            .autocapitalization(UITextAutocapitalizationType.none)

                        if settings.deepl_api_key == "" {
                            Link(NSLocalizedString("Get API Key", comment: "Button to navigate to DeepL website to get a translation API key."), destination: URL(string: "https://www.deepl.com/pro-api")!)
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

                let bundleShortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
                let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
                Section(NSLocalizedString("Version", comment: "Section title for displaying the version number of the Damus app.")) {
                    Text("\(bundleShortVersion) (\(bundleVersion))", comment: "Text indicating which version of the Damus app is running. Should typically not need to be translated.")
                }
            }
        }
        .navigationTitle(NSLocalizedString("Settings", comment: "Navigation title for Settings view."))
        .navigationBarTitleDisplayMode(.large)
        .alert(NSLocalizedString("Permanently Delete Account", comment: "Alert for deleting the users account."), isPresented: $confirm_delete_account) {
            TextField(NSLocalizedString("Type DELETE to delete", comment: "Text field prompt asking user to type the word DELETE to confirm that they want to proceed with deleting their account. The all caps lock DELETE word should not be translated. Everything else should."), text: $delete_text)
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

    var libretranslate_view: some View {
        VStack {
            Picker(NSLocalizedString("Server", comment: "Prompt selection of LibreTranslate server to perform machine translations on notes"), selection: $settings.libretranslate_server) {
                ForEach(LibreTranslateServer.allCases, id: \.self) { server in
                    Text(server.model.displayName)
                        .tag(server.model.tag)
                }
            }

            TextField(NSLocalizedString("URL", comment: "Example URL to LibreTranslate server"), text: $settings.libretranslate_url)
                .disableAutocorrection(true)
                .disabled(settings.libretranslate_server != .custom)
                .autocapitalization(UITextAutocapitalizationType.none)
            HStack {
                let libretranslate_api_key_placeholder = NSLocalizedString("API Key (optional)", comment: "Prompt for optional entry of API Key to use translation server.")
                if show_api_key {
                    TextField(libretranslate_api_key_placeholder, text: $settings.libretranslate_api_key)
                        .disableAutocorrection(true)
                        .autocapitalization(UITextAutocapitalizationType.none)
                    if settings.libretranslate_api_key != "" {
                        Button(NSLocalizedString("Hide API Key", comment: "Button to hide the LibreTranslate server API key.")) {
                            show_api_key = false
                        }
                    }
                } else {
                    SecureField(libretranslate_api_key_placeholder, text: $settings.libretranslate_api_key)
                        .disableAutocorrection(true)
                        .autocapitalization(UITextAutocapitalizationType.none)
                    if settings.libretranslate_api_key != "" {
                        Button(NSLocalizedString("Show API Key", comment: "Button to show the LibreTranslate server API key.")) {
                            show_api_key = true
                        }
                    }
                }
            }
        }
    }

    var deepl_view: some View {
        VStack {
            Picker(NSLocalizedString("Plan", comment: "Prompt selection of DeepL subscription plan to perform machine translations on notes"), selection: $settings.deepl_plan) {
                ForEach(DeepLPlan.allCases, id: \.self) { server in
                    Text(server.model.displayName)
                        .tag(server.model.tag)
                }
            }

            HStack {
                let deepl_api_key_placeholder = NSLocalizedString("API Key (required)", comment: "Prompt for required entry of API Key to use translation server.")
                if show_api_key {
                    TextField(deepl_api_key_placeholder, text: $settings.deepl_api_key)
                        .disableAutocorrection(true)
                        .autocapitalization(UITextAutocapitalizationType.none)
                    if settings.deepl_api_key != "" {
                        Button(NSLocalizedString("Hide API Key", comment: "Button to hide the DeepL translation API key.")) {
                            show_api_key = false
                        }
                    }
                } else {
                    SecureField(deepl_api_key_placeholder, text: $settings.deepl_api_key)
                        .disableAutocorrection(true)
                        .autocapitalization(UITextAutocapitalizationType.none)
                    if settings.deepl_api_key != "" {
                        Button(NSLocalizedString("Show API Key", comment: "Button to show the DeepL translation API key.")) {
                            show_api_key = true
                        }
                    }
                }
                if settings.deepl_api_key == "" {
                    Link(NSLocalizedString("Get API Key", comment: "Button to navigate to DeepL website to get a translation API key."), destination: URL(string: "https://www.deepl.com/pro-api")!)
                }
            }
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
