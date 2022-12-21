//
//  EditAccountView.swift
//  damus
//
//  Created by Sam DuBois on 12/20/22.
//

import SwiftUI

struct EditAccountView: View {
    
    @Environment(\.colorScheme) var scheme
    
    @EnvironmentObject var viewModel: DamusViewModel
    @Environment(\.dismiss) var dismiss
    
    @State var account: AccountModel = AccountModel()
    @State var loading: Bool = true
    @State var error: Error?
    
    var body: some View {
        NavigationView {
            if let state = viewModel.damus_state, !loading {
                Form {
                    HStack {
                        Spacer()
                        ProfilePicView(pubkey: state.pubkey, size: 100, highlight: .custom(scheme == .light ? .white : .black, 3), profiles: state.profiles)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    
                    Section(header: Text("Photo")) {
                        TextField("Photo URL", text: $account.picture)
                    }
                    
                    Section(header: Text("Details")) {
                        TextField("Username", text: $account.real_name)
                        TextField("Personal Name", text: $account.nick_name)
                        TextEditor(text: $account.about)
                            .frame(height: 150)
                        
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            self.loading = true
                            viewModel.damus_state!.pool.register_handler(sub_id: "editaccount", handler: handle_event)
                            viewModel.damus_state!.pool.connect()
                        } label: {
                            Text("Save")
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if let state = viewModel.damus_state {
    
                guard let profile = state.profiles.lookup(id: state.pubkey) else { return }
    
                account = AccountModel(keys: state.keypair, real: profile.display_name ?? "", user: profile.name ?? "", about: profile.about ?? "", picture: profile.picture ?? "")
                
                loading = false
            }
        }
    }

    func handle_event(relay: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event(let wsev):
            switch wsev {
            case .connected:
                let metadata = account_to_metadata(account)
                let m_metadata_ev = make_metadata_event(keypair: account.keypair, metadata: metadata)
                
                if let state = viewModel.damus_state {
                    if let metadata_ev = m_metadata_ev {
                        state.pool.send(.event(metadata_ev))
                    }
                }
                
            case .error(let error):
                self.loading = false
                print(error)
            default:
                dismiss()
            }
        case .nostr_event(let resp):
            switch resp {
            case .notice(let msg):
                // TODO handle message
//                self.loading = false
//                self.error = msg
                print(msg)
            case .event:
                print("event in account edit request?")
            case .eose:
                break
            }
        }
    }
}

struct EditAccountView_Previews: PreviewProvider {
    static var previews: some View {
        EditAccountView()
            .environmentObject(DamusViewModel())
    }
}
