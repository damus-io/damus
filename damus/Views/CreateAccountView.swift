//
//  CreateAccountView.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI

struct CreateAccountView: View {
    @StateObject var account: CreateAccountModel = CreateAccountModel()
    @State var is_light: Bool = false
    @State var is_done: Bool = false
    
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
                Text("optional")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    func SignupForm<FormContent: View>(@ViewBuilder content: () -> FormContent) -> some View {
        return VStack(alignment: .leading, spacing: 10.0, content: content)
    }
    
    func regen_key() {
        let keypair = generate_new_keypair()
        self.account.pubkey = keypair.pubkey
        self.account.privkey = keypair.privkey
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            DamusGradient()
            
            VStack {
                Text("Create Account")
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                ProfilePictureSelector(pubkey: account.pubkey)
                
                HStack(alignment: .top) {
                    VStack {
                        Text("   ")
                            .foregroundColor(.white)
                    }
                    VStack {
                        SignupForm {
                            FormLabel("Username")
                            HStack(spacing: 0.0) {
                                Text("@")
                                    .foregroundColor(.white)
                                    .padding(.leading, -25.0)
                                
                                FormTextInput("satoshi", text: $account.nick_name)
                                    .textInputAutocapitalization(.never)
                                
                            }
                            
                            FormLabel("Display Name", optional: true)
                            FormTextInput("Satoshi Nakamoto", text: $account.real_name)
                                .textInputAutocapitalization(.words)
                            
                            FormLabel("About", optional: true)
                            FormTextInput("Creator(s) of Bitcoin. Absolute legend.", text: $account.about)
                            
                            FormLabel("Account ID")
                                .onTapGesture {
                                    regen_key()
                                }
                            
                            KeyInput($account.pubkey)
                                .onTapGesture {
                                    regen_key()
                                }
                        }
                    }
                }
                
                NavigationLink(destination: SaveKeysView(account: account), isActive: $is_done) {
                    EmptyView()
                }
                DamusWhiteButton("Create") {
                    self.is_done = true
                }
                .padding()
            }
            .padding(.leading, 14.0)
            .padding(.trailing, 20.0)
            
        }
        .navigationBarTitleDisplayMode(.inline)
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

func KeyInput(_ text: Binding<String>) -> some View {
    return Text("\(text.wrappedValue)")
        .textSelection(.enabled)
        .font(.callout.monospaced())
        .foregroundColor(.white)
}

