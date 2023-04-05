//
//  KeySettingsView.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI
import LocalAuthentication

struct KeySettingsView: View {
    let keypair: Keypair
    
    @State var privkey: String
    @State var privkey_copied: Bool = false
    @State var pubkey_copied: Bool = false
    @State var show_privkey: Bool = false
    @State var has_authenticated_locally: Bool = false
    
    @Environment(\.dismiss) var dismiss
    
    init(keypair: Keypair) {
        _privkey = State(initialValue: keypair.privkey_bech32 ?? "")
        self.keypair = keypair
    }
    
    var ShowSecToggle: some View {
        Toggle(NSLocalizedString("Show", comment: "Toggle to show or hide user's secret account login key."), isOn: $show_privkey)
            .onChange(of: show_privkey) { newValue in
                if newValue {
                    authenticate_locally(has_authenticated_locally) { success in
                        self.has_authenticated_locally = success
                        self.show_privkey = success
                    }
                }
            }
    }
    
    // TODO: (jb55) could be more general but not gonna worry about it atm
    func CopyButton(is_pk: Bool) -> some View {
        return Button(action: {
            let copyKey = {
                UIPasteboard.general.string = is_pk ? self.keypair.pubkey_bech32 : self.privkey
                self.privkey_copied = !is_pk
                self.pubkey_copied = is_pk
    
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            
            if is_pk {
                copyKey()
                return
            }
            
            if has_authenticated_locally {
                copyKey()
                return
            }
            
            authenticate_locally(has_authenticated_locally) { success in
                self.has_authenticated_locally = success
                if success {
                    copyKey()
                }
            }
        }) {
            let copied = is_pk ? self.pubkey_copied : self.privkey_copied
            Image(systemName: copied ? "checkmark.circle" : "doc.on.doc")
        }
    }
    
    var body: some View {
        Form {
            Section(NSLocalizedString("Public Account ID", comment: "Section title for the user's public account ID.")) {
                HStack {
                    Text(keypair.pubkey_bech32)
                    
                    CopyButton(is_pk: true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            
            if let sec = keypair.privkey_bech32 {
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
                    
                    ShowSecToggle
                }
            }
            
        }
        .navigationTitle("Keys")
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
}

struct KeySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let kp = generate_new_keypair()
        KeySettingsView(keypair: kp)
    }
}

func authenticate_locally(_ has_authenticated_locally: Bool, completion: @escaping (Bool) -> Void) {
    // Need to authenticate only once while ConfigView is presented
    guard !has_authenticated_locally else {
        completion(true)
        return
    }
    let context = LAContext()
    if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: NSLocalizedString("Local authentication to access private key", comment: "Face ID usage description shown when trying to access private key")) { success, error in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    } else {
        // If there's no authentication set up on the device, let the user copy the key without it
        completion(true)
    }
}

