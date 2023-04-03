//
//  CreateAccountView.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI

struct CreateAccountView: View {
    @StateObject var account: CreateAccountModel = CreateAccountModel()
    @StateObject var profileUploadObserver = ImageUploadingObserver()
    
    @State var is_light: Bool = false
    @State var is_done: Bool = false
    @State var reading_eula: Bool = false
    @State var profile_image: URL? = nil
    
    func SignupForm<FormContent: View>(@ViewBuilder content: () -> FormContent) -> some View {
        return VStack(alignment: .leading, spacing: 10.0, content: content)
    }
    
    func regen_key() {
        let keypair = generate_new_keypair()
        self.account.pubkey = keypair.pubkey
        self.account.privkey = keypair.privkey!
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            DamusGradient()
            
            VStack {
                Text("Create Account")
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                EditProfilePictureView(pubkey: account.pubkey, uploadObserver: profileUploadObserver, callback: uploadedProfilePicture(image_url:))
                
                HStack(alignment: .top) {
                    VStack {
                        Text(verbatim: "   ")
                            .foregroundColor(.white)
                    }
                    VStack {
                        SignupForm {
                            FormLabel(NSLocalizedString("Username", comment: "Label to prompt username entry."))
                            HStack(spacing: 0.0) {
                                Text(verbatim: "@")
                                    .foregroundColor(.white)
                                    .padding(.leading, -25.0)
                                
                                FormTextInput(NSLocalizedString("satoshi", comment: "Example username of Bitcoin creator(s), Satoshi Nakamoto."), text: $account.nick_name)
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.never)
                                
                            }
                            
                            FormLabel(NSLocalizedString("Display Name", comment: "Label to prompt display name entry."), optional: true)
                            FormTextInput(NSLocalizedString("Satoshi Nakamoto", comment: "Name of Bitcoin creator(s)."), text: $account.real_name)
                                .textInputAutocapitalization(.words)
                            
                            FormLabel(NSLocalizedString("About", comment: "Label to prompt for about text entry for user to describe about themself."), optional: true)
                            FormTextInput(NSLocalizedString("Creator(s) of Bitcoin. Absolute legend.", comment: "Example description about Bitcoin creator(s), Satoshi Nakamoto."), text: $account.about)
                            
                            FormLabel(NSLocalizedString("Account ID", comment: "Label to indicate the public ID of the account."))
                                .onTapGesture {
                                    regen_key()
                                }
                            
                            KeyText($account.pubkey)
                                .onTapGesture {
                                    regen_key()
                                }
                        }
                    }
                }
                
                NavigationLink(destination: SaveKeysView(account: account), isActive: $is_done) {
                    EmptyView()
                }
                
                DamusWhiteButton(NSLocalizedString("Create", comment: "Button to create account.")) {
                    self.is_done = true
                }
                .padding()
                .disabled(profileUploadObserver.isLoading)
                .opacity(profileUploadObserver.isLoading ? 0.5 : 1)
            }
            .padding(.leading, 14.0)
            .padding(.trailing, 20.0)
            
        }
        .dismissKeyboardOnTap()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
    }
    
    func uploadedProfilePicture(image_url: URL?) {
        account.profile_image = image_url?.absoluteString
    }
}

struct BackNav: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Image(systemName: "chevron.backward")
        .foregroundColor(.white)
        .onTapGesture {
            self.dismiss()
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

struct CreateAccountView_Previews: PreviewProvider {
    static var previews: some View {
        let model = CreateAccountModel(real: "", nick: "jb55", about: "")
        return CreateAccountView(account: model)
    }
}

func KeyText(_ text: Binding<String>) -> some View {
    let decoded = hex_decode(text.wrappedValue)!
    let bechkey = bech32_encode(hrp: PUBKEY_HRP, decoded)
    return Text(bechkey)
        .textSelection(.enabled)
        .font(.callout.monospaced())
        .foregroundColor(.white)
}

func FormTextInput(_ title: String, text: Binding<String>) -> some View {
    return TextField("", text: text)
        .placeholder(when: text.wrappedValue.isEmpty) {
            Text(title).foregroundColor(.white.opacity(0.4))
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 4.0).opacity(0.2)
        }
        .foregroundColor(.white)
        .font(.body.bold())
}

func FormLabel(_ title: String, optional: Bool = false) -> some View {
    return HStack {
        Text(title)
                .bold()
                .foregroundColor(.white)
        if optional {
            Text("optional", comment: "Label indicating that a form input is optional.")
                .font(.callout)
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

