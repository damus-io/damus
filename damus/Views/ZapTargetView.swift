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
    }
    
    func handleInput() -> Bool {
        let parsed = parse_key(input)
        if parsed?.is_pub ?? false {
            let decoded = try? bech32_decode(input)
            input = hex_encode(decoded!.data)
        }
        if input == damus_state.pubkey {
            showAlert = true
            alertMessage = "Cannot add yourself as a zap target"
            return false
        }
        return true
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
            ProfilePicView(pubkey: zap_pubkey, size: 90.0, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
            let profile = damus_state.profiles.lookup(id: zap_pubkey)
            let display_name = Profile.displayName(profile: profile, pubkey: zap_pubkey).display_name
            Text(" \(display_name)")
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
            
            let parsed = parse_key(input)

            if(!zap_pubkey.isEmpty) {
                ZapTargetAction(text: "Remove", comment: "Button to remove zap target", action: {
                    input = ""
                    zap_pubkey = ""
                })
            } else if (!input.isEmpty && parsed != nil) {
                ZapTargetAction(text: "Confirm", comment: "Button to confirm zap target", action: {
                    if handleInput() {
                        zap_pubkey = input
                        presentationMode.wrappedValue.dismiss()
                    }
                })
            }

            if input.hasPrefix("@") {
                SelectUsersPubkey
            }
        }
        .padding()
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Sorry"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}

struct ZapTargetView_Previews: PreviewProvider {
    static var previews: some View {
        ZapTargetView(damus_state: test_damus_state(), zap_pubkey: .constant(""))
    }
}

