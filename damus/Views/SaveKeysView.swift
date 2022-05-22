//
//  SaveKeysView.swift
//  damus
//
//  Created by William Casarin on 2022-05-21.
//

import SwiftUI

struct SaveKeysView: View {
    let account: CreateAccountModel
    @State var is_done: Bool = false
    @State var pub_copied: Bool = false
    @State var priv_copied: Bool = false
    
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
                
                Text("This is your account ID, you can give this to your friends so that they can follow you")
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                SaveKeyView(text: account.pubkey, is_copied: $pub_copied)
                    .padding(.bottom, 10)
                
                Text("Private Key")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                Text("This is your secret account key. You need this to access your account. Don't share this with anyone! Save it in a password manager and keep it safe!")
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                SaveKeyView(text: account.privkey, is_copied: $priv_copied)
                    .padding(.bottom, 10)
                
                if pub_copied && priv_copied {
                    DamusWhiteButton("Let's go!") {
                        save_keypair(pubkey: account.pubkey, privkey: account.privkey)
                        notify(.login, ())
                    }
                }
            }
            .padding(20)
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
