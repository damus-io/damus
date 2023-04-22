//
//  ZapTargetView.swift
//  damus
//
//  Created by eric on 4/5/23.
//

import SwiftUI

struct ZapTargetView: View {
    
    let damus_state: DamusState
    @State var input: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State var searching: Bool = false
    @Binding var zap_pubkey: String
    @Binding var display_name: String
    @FocusState private var isFocused: Bool
    
    @Environment(\.presentationMode) var presentationMode
    
    var users: [SearchedUser] {
        guard let contacts = damus_state.contacts.event else {
            return search_profiles(profiles: damus_state.profiles, search: String(input.dropFirst()))
        }
        
        return search_users_for_autocomplete(profiles: damus_state.profiles, tags: contacts.tags, search: String(input.dropFirst()))
    }
    
    func on_user_tapped(user: SearchedUser) {
        if user.pubkey == damus_state.pubkey {
            showAlert = true
            alertMessage = "Cannot add yourself as a zap target"
            return
        }
        
        guard let lnurl = user.profile?.lud06 ?? user.profile?.lud16 else {
            showAlert = true
            alertMessage = "Failed to load profile"
            return
        }
        
        if lnurl.isEmpty {
            showAlert = true
            alertMessage = "Did not find a LNURL for this user."
            return
        }
        
        input = user.pubkey
        display_name = Profile.displayName(profile: user.profile, pubkey: user.pubkey).display_name
    }
    
    var SelectUsersPubkey: some View {
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
    
    var ZapTargetInput: some View {
        HStack{
            Image(systemName: "doc.on.clipboard")
                .foregroundColor(.accentColor)
                .onTapGesture {
                    if let pastedZapTarget = UIPasteboard.general.string {
                        self.input = pastedZapTarget
                    }
                }
            TextField(NSLocalizedString("Enter a pubkey or find by username @", comment: "Placeholder instructions for entering a zap target."), text: $input)
                .padding(5)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .disabled(!zap_pubkey.isEmpty)
            
            Label("", systemImage: "xmark.circle.fill")
                .foregroundColor(.accentColor)
                .opacity((input == "") ? 0.0 : 1.0)
                .opacity((!zap_pubkey.isEmpty) ? 0.0 : 1.0)
                .onTapGesture {
                    self.input = ""
                }
        }
        .padding(10)
        .background(.secondary.opacity(0.2))
        .cornerRadius(10)
    }
    
    var ZapTargetProfile: some View {
        VStack {
            ProfilePicView(pubkey: zap_pubkey, size: 90.0, highlight: .none, profiles: damus_state.profiles)
            Text(display_name)
                .font(.headline)
        }
    }
    
    func ZapTargetAction(text: String, comment: String, action: @escaping () -> ()) -> some View {
        Button(action: action) {
            Text(NSLocalizedString(text, comment: comment))
                .font(.system(size: 16, weight: .bold))
                .frame(minWidth: 300, maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .center)
                .foregroundColor(.white)
                .background(LINEAR_GRADIENT)
                .clipShape(Capsule())
                .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 10) {

            (Text(Image(systemName: "bolt")).foregroundColor(DamusColors.yellow) + Text(NSLocalizedString(" Zap Target ", comment: "Text indicating that the view is used for editing where zaps are sent to.")))
                .font(.system(size: 32, weight: .heavy))
            
            Text(NSLocalizedString("All zaps will be sent to this user", comment: "Description of zap target."))
                .font(.system(size: 16, weight: .semibold))
                .padding(.bottom, 40)
            
            if(!zap_pubkey.isEmpty) {
                ZapTargetProfile
            } else {
                ZapTargetInput
            }

            if(!zap_pubkey.isEmpty) {
                ZapTargetAction(text: "Remove", comment: "Button to remove zap target", action: {
                    input = ""
                    display_name = ""
                    zap_pubkey = ""
                    isFocused = false
                })
            } else if (!input.isEmpty) {
                ZapTargetAction(text: "Confirm", comment: "Button to confirm zap target", action: {
                    zap_pubkey = input
                    presentationMode.wrappedValue.dismiss()
                    isFocused = false
                })
            }

            if input.hasPrefix("@") {
                SelectUsersPubkey
            }
        }
        .padding()
        .onAppear() {
            if !zap_pubkey.isEmpty {
                input = display_name
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Sorry"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}

struct ZapTargetView_Previews: PreviewProvider {
    static var previews: some View {
        ZapTargetView(damus_state: test_damus_state(), zap_pubkey: .constant(""), display_name: .constant(""))
    }
}

