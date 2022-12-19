//
//  SaveKeysView.swift
//  damus
//
//  Created by William Casarin on 2022-05-21.
//

import SwiftUI

struct SaveKeysView: View {
    let account: CreateAccountModel
    let pool: RelayPool = RelayPool()
    @State var is_done: Bool = false
    @State var pub_copied: Bool = false
    @State var priv_copied: Bool = false
    @State var loading: Bool = false
    @State var error: String? = nil
    
    var body: some View {
        ZStack(alignment: .top) {
            DamusGradient()
            
            VStack(alignment: .center) {
                Text("Welcome, \(account.rendered_name)!")
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                Text("Before we get started, you'll need to save your account info, otherwise you won't be able to login in the future if you ever uninstall Damus.")
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                Text("Public Key")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                Text("This is your account ID, you can give this to your friends so that they can follow you. Click to copy.")
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                SaveKeyView(text: account.pubkey_bech32, is_copied: $pub_copied)
                    .padding(.bottom, 10)
                
                if pub_copied {
                    Text("Private Key")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.bottom, 10)
                    
                    Text("This is your secret account key. You need this to access your account. Don't share this with anyone! Save it in a password manager and keep it safe!")
                        .foregroundColor(.white)
                        .padding(.bottom, 10)
                    
                    SaveKeyView(text: account.privkey_bech32, is_copied: $priv_copied)
                        .padding(.bottom, 10)
                }
                
                if pub_copied && priv_copied {
                    if loading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else if let err = error {
                        Text("Error: \(err)")
                            .foregroundColor(.red)
                        DamusWhiteButton("Retry") {
                            complete_account_creation(account)
                        }
                    } else {
                        DamusWhiteButton("Let's go!") {
                            complete_account_creation(account)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
    }
    
    func complete_account_creation(_ account: CreateAccountModel) {
        for relay in BOOTSTRAP_RELAYS {
            add_rw_relay(self.pool, relay)
        }

        self.pool.register_handler(sub_id: "signup", handler: handle_event)
        
        self.loading = true
        
        self.pool.connect()
    }
    
    func handle_event(relay: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event(let wsev):
            switch wsev {
            case .connected:
                let metadata = create_account_to_metadata(account)
                let m_metadata_ev = make_metadata_event(keypair: account.keypair, metadata: metadata)
                let m_contacts_ev = make_first_contact_event(keypair: account.keypair)
                
                if let metadata_ev = m_metadata_ev {
                    self.pool.send(.event(metadata_ev))
                }
                if let contacts_ev = m_contacts_ev {
                    self.pool.send(.event(contacts_ev))
                }
                
                save_keypair(pubkey: account.pubkey, privkey: account.privkey)
                notify(.login, account.keypair)
            case .error(let err):
                self.loading = false
                self.error = "\(err.debugDescription)"
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
            }
        }
    }
}

struct SaveKeyView: View {
    let text: String
    @Binding var is_copied: Bool
    
    func copy_text() {
        UIPasteboard.general.string = text
        is_copied = true
    }
    
    var body: some View {
        HStack {
            Button(action: copy_text) {
                Label("", systemImage: is_copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundColor(is_copied ? .green : .white)
                    .background {
                        if is_copied {
                            Circle()
                                .foregroundColor(.white)
                                .frame(width: 25, height: 25, alignment: .center)
                                .padding(.leading, -8)
                                .padding(.top, 1)
                        } else {
                            EmptyView()
                        }
                    }
            }
          
            Text(text)
                .padding(5)
                .background {
                    RoundedRectangle(cornerRadius: 4.0).opacity(0.2)
                }
                .textSelection(.enabled)
                .font(.callout.monospaced())
                .foregroundColor(.white)
                .onTapGesture {
                    copy_text()
                }
        }
    }
}

struct SaveKeysView_Previews: PreviewProvider {
    static var previews: some View {
        let model = CreateAccountModel(real: "William", nick: "jb55", about: "I'm me")
        SaveKeysView(account: model)
    }
}
