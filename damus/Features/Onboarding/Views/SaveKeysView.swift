//
//  SaveKeysView.swift
//  damus
//
//  Created by William Casarin on 2022-05-21.
//

import SwiftUI
import Security

struct SaveKeysView: View {
    let account: CreateAccountModel
    let pool: RelayPool = RelayPool(ndb: Ndb()!)
    @State var loading: Bool = false
    @State var error: String? = nil

    @State private var credential_handler = CredentialHandler()
    @State private var selectedStorageMode: KeyStorageMode = KeyStorageSettings.mode
    @State private var showStorageInfo: Bool = false

    @FocusState var pubkey_focused: Bool
    @FocusState var privkey_focused: Bool

    let first_contact_event: NdbNote?
    let first_relay_list_event: NdbNote?

    init(account: CreateAccountModel) {
        self.account = account
        self.first_contact_event = make_first_contact_event(keypair: account.keypair)
        self.first_relay_list_event = NIP65.RelayList(relays: get_default_bootstrap_relays()).toNostrEvent(keypair: account.full_keypair)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .center) {

                Spacer()
                
                Image("logo-nobg")
                    .resizable()
                    .shadow(color: DamusColors.purple, radius: 2)
                    .frame(width: 56, height: 56, alignment: .center)
                    .padding(.top, 20.0)
                
                if account.rendered_name.isEmpty {
                    Text("Welcome!", comment: "Text to welcome user.")
                        .font(.title)
                        .fontWeight(.heavy)
                        .foregroundStyle(DamusLogoGradient.gradient)
                } else {
                    Text("Welcome, \(account.rendered_name)!", comment: "Text to welcome user.")
                        .font(.title)
                        .fontWeight(.heavy)
                        .foregroundStyle(DamusLogoGradient.gradient)
                }
                
                Text("Save your login info?", comment: "Ask user if they want to save their account information.")
                    .font(.title)
                    .fontWeight(.heavy)
                    .foregroundColor(DamusColors.neutral6)
                    .padding(.top, 5)
                
                Text("We'll save your account key, so you won't need to enter it manually next time you log in.", comment: "Reminder to user that they should save their account information.")
                    .font(.system(size: 14))
                    .foregroundColor(DamusColors.neutral6)
                    .padding(.top, 2)
                    .multilineTextAlignment(.center)

                // Storage mode picker
                VStack(spacing: 12) {
                    Text("How should we store your key?", comment: "Prompt asking user how to store their key")
                        .font(.headline)
                        .foregroundColor(DamusColors.neutral6)
                        .padding(.top, 20)

                    Picker("", selection: $selectedStorageMode) {
                        ForEach(KeyStorageMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    Text(selectedStorageMode.description)
                        .font(.caption)
                        .foregroundColor(DamusColors.neutral6)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .fixedSize(horizontal: false, vertical: true)

                    if selectedStorageMode == .localOnly {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Make sure to back up your key separately!", comment: "Warning about local-only key storage")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    #if targetEnvironment(simulator)
                    if selectedStorageMode == .iCloudSync {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Simulator: iCloud sync requires signing into iCloud in Settings.", comment: "Simulator warning for iCloud sync")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    #endif
                }
                .padding(.bottom, 20)

                Spacer()
                
                if loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else if let err = error {
                    Text("Error: \(err)", comment: "Error message indicating why saving keys failed.")
                        .foregroundColor(.red)
                    
                    Button(action: {
                        Task { await complete_account_creation(account) }
                    }) {
                        HStack {
                            Text("Retry", comment:  "Button to retry completing account creation after an error occurred.")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 12, alignment: .center)
                    }
                    .buttonStyle(GradientButtonStyle())
                    .padding(.top, 20)
                } else {
                    
                    Button(action: {
                        // Apply the selected storage mode
                        KeyStorageSettings.mode = selectedStorageMode
                        save_key(account)
                        Task { await complete_account_creation(account) }
                    }) {
                        HStack {
                            Text("Save", comment:  "Button to save key, complete account creation, and start using the app.")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 12, alignment: .center)
                    }
                    .buttonStyle(GradientButtonStyle())
                    .padding(.top, 20)
                    .accessibilityIdentifier(AppAccessibilityIdentifiers.sign_up_save_keys_button.rawValue)
                    
                    Button(action: {
                        Task { await complete_account_creation(account) }
                    }) {
                        HStack {
                            Text("Not now", comment:  "Button to not save key, complete account creation, and start using the app.")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 12, alignment: .center)
                    }
                    .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15), cornerRadius: 12))
                    .padding(.top, 20)
                    .accessibilityIdentifier(AppAccessibilityIdentifiers.sign_up_skip_save_keys_button.rawValue)
                }
            }
            .padding(20)
        }
        .background(DamusBackground(maxHeight: UIScreen.main.bounds.size.height/2), alignment: .top)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())

    }
    
    func save_key(_ account: CreateAccountModel) {
        // Only use Safari shared credentials for iCloud sync mode.
        // For local-only mode, keys are stored via AccountsStore with Secure Enclave
        // encryption - calling CredentialHandler would defeat the purpose by syncing
        // the key via iCloud shared web credentials.
        if KeyStorageSettings.mode == .iCloudSync {
            credential_handler.save_credential(pubkey: account.pubkey, privkey: account.privkey)
        }
    }
    
    func complete_account_creation(_ account: CreateAccountModel) async {
        guard let first_contact_event else {
            error = NSLocalizedString("Could not create your initial contact list event. This is a software bug, please contact Damus support via support@damus.io or through our Nostr account for help.", comment: "Error message to the user indicating that the initial contact list failed to be created.")
            return
        }
        guard let first_relay_list_event else {
            error = NSLocalizedString("Could not create your initial relay list. This is a software bug, please contact Damus support via support@damus.io or through our Nostr account for help.", comment: "Error message to the user indicating that the initial relay list failed to be created.")
            return
        }
        // Save contact list to storage right away so that we don't need to depend on the network to complete this important step
        self.save_to_storage(first_contact_event: first_contact_event, first_relay_list_event: first_relay_list_event, for: account)
        
        let bootstrap_relays = load_bootstrap_relays(pubkey: account.pubkey)
        for relay in bootstrap_relays {
            await add_rw_relay(self.pool, relay)
        }
        
        self.loading = true
                
        Task {
            await self.pool.connect()
            
            let stream = AsyncStream<(RelayURL, NostrConnectionEvent)> { streamContinuation in
                Task { await self.pool.register_handler(sub_id: "signup", filters: nil, handler: streamContinuation) }
            }
            for await (relayUrl, connectionEvent) in stream {
                await handle_event(relay: relayUrl, ev: connectionEvent)
            }
        }
    }
    
    func save_to_storage(first_contact_event: NdbNote, first_relay_list_event: NdbNote, for account: CreateAccountModel) {
        // Send to NostrDB so that we have a local copy in storage
        self.pool.send_raw_to_local_ndb(.typical(.event(first_contact_event)))
        self.pool.send_raw_to_local_ndb(.typical(.event(first_relay_list_event)))
        
        // Save the ID to user settings so that we can easily find it later.
        let settings = UserSettingsStore.globally_load_for(pubkey: account.pubkey)
        settings.latest_contact_event_id_hex = first_contact_event.id.hex()
        settings.latestRelayListEventIdHex = first_relay_list_event.id.hex()
    }

    func handle_event(relay: RelayURL, ev: NostrConnectionEvent) async {
        switch ev {
        case .ws_connection_event(let wsev):
            switch wsev {
            case .connected:
                let metadata = create_account_to_metadata(account)
                
                if let keypair = account.keypair.to_full(),
                   let metadata_ev = make_metadata_event(keypair: keypair, metadata: metadata) {
                    await self.pool.send(.event(metadata_ev))
                }
                
                if let first_contact_event {
                    await self.pool.send(.event(first_contact_event))
                }
                
                if let first_relay_list_event {
                    await self.pool.send(.event(first_relay_list_event))
                }
                
                let store = AccountsStore.shared
                store.addOrUpdate(account.keypair, savePriv: true)
                OnboardingSession.shared.end()
                store.setActive(account.pubkey)
                notify(.login(store.activeKeypair ?? account.keypair))
                
            case .error(let err):
                self.loading = false
                self.error = String(describing: err)
            default:
                break
            }
        case .nostr_event(let resp):
            switch resp {
            case .notice(let msg):
                // TODO handle message
                self.loading = false
                self.error = msg
                print(msg)
            case .event:
                print("event in signup?")
            case .eose:
                break
            case .ok:
                break
            case .auth:
                break
            }
        }
    }
}

struct SaveKeysView_Previews: PreviewProvider {
    static var previews: some View {
        let model = CreateAccountModel(display_name: "William", name: "jb55", about: "I'm me")
        SaveKeysView(account: model)
    }
}

func create_account_to_metadata(_ model: CreateAccountModel) -> Profile {
    return Profile(name: model.name, display_name: model.display_name, about: model.about, picture: model.profile_image?.absoluteString, banner: nil, website: nil, lud06: nil, lud16: nil, nip05: nil, damus_donation: nil)
}
