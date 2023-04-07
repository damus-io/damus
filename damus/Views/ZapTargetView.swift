//
//  ZapTargetView.swift
//  damus
//
//  Created by eric on 4/5/23.
//

import SwiftUI

struct ZapTargetView: View {
    
    let damus_state: DamusState
    @State var zaptarget_input: String = ""
    @State private var showAlert: Bool = false
    @Binding var zaptarget: String
    @FocusState private var isFocused: Bool
    
    @Environment(\.presentationMode) var presentationMode
    
    var users: [SearchedUser] {
        guard let contacts = damus_state.contacts.event else {
            return search_profiles(profiles: damus_state.profiles, search: String(zaptarget_input.dropFirst()))
        }
        
        return search_users_for_autocomplete(profiles: damus_state.profiles, tags: contacts.tags, search: String(zaptarget_input.dropFirst()))
    }
    
    func on_user_tapped(user: SearchedUser) {
        guard let lnurl = user.profile?.lud06 ?? user.profile?.lud16 else {
            showAlert = true
            return
        }
        if lnurl.isEmpty {
            showAlert = true
        } else {
            zaptarget_input = lnurl
        }
    }
    
    var SelectUsersLNURL: some View {
        ScrollView {
            LazyVStack {
                Divider()
                if users.count == 0 {
                    EmptyUserSearchView()
                } else {
                    ForEach(users) { user in
                        UserView(damus_state: damus_state, pubkey: user.pubkey)
                            .onTapGesture {
                                on_user_tapped(user: user)
                            }
                    }
                }
            }
        }
        .onAppear() {
            isFocused = false
        }
    }
    
    var body: some View {
        VStack {
            Text("Zap Target", comment: "Text indicating that the view is used for editing where zaps are sent to.")
                .font(.headline)
            
            Text("All zaps will be sent to this LNURL", comment: "Description of zap target")
            
            HStack{
                Image(systemName: "doc.on.clipboard")
                    .foregroundColor(.accentColor)
                    .onTapGesture {
                        if let pastedZapTarget = UIPasteboard.general.string {
                            self.zaptarget_input = pastedZapTarget
                        }
                    }
                TextField(NSLocalizedString("LNURL or find by username @", comment: "Placeholder example for LNURL."), text: $zaptarget_input)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .disabled(!zaptarget.isEmpty)
                
                Label("", systemImage: "xmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .opacity((zaptarget_input == "") ? 0.0 : 1.0)
                    .opacity((!zaptarget.isEmpty) ? 0.0 : 1.0)
                    .onTapGesture {
                        self.zaptarget_input = ""
                    }
            }
            .padding(10)
            .background(.secondary.opacity(0.2))
            .cornerRadius(10)
            
            HStack{
                
                if(!zaptarget.isEmpty) {
                    Button(action: {
                        zaptarget_input = ""
                        zaptarget = ""
                        isFocused = false
                    }) {
                        Text(NSLocalizedString("Remove", comment: "Button to remove zap target"))
                            .font(.system(size: 16, weight: .bold))
                            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .center)
                            .foregroundColor(.white)
                            .background(LINEAR_GRADIENT)
                            .clipShape(Capsule())
                            .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }
                } else if (!zaptarget_input.isEmpty) {
                    Button(action: {
                        zaptarget = zaptarget_input
                        presentationMode.wrappedValue.dismiss()
                        isFocused = false
                    }) {
                        Text(NSLocalizedString("Confirm", comment: "Button to confirm zap target"))
                            .font(.system(size: 16, weight: .bold))
                            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .center)
                            .foregroundColor(.white)
                            .background(LINEAR_GRADIENT)
                            .clipShape(Capsule())
                            .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }
                }
            }

            if zaptarget_input.hasPrefix("@") {
                SelectUsersLNURL
            }
        }
        .padding()
        .onAppear() {
            if !zaptarget.isEmpty {
                zaptarget_input = zaptarget
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Sorry"), message: Text("LNURL not found for this user."), dismissButton: .default(Text("OK")))
        }
    }
}

struct ZapTargetView_Previews: PreviewProvider {
    static var previews: some View {
        ZapTargetView(damus_state: test_damus_state(), zaptarget: .constant(""))
    }
}

