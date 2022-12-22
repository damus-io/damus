//
//  LoginView.swift
//  damus
//
//  Created by William Casarin on 2022-05-22.
//

import SwiftUI

enum ParsedKey {
    case pub(String)
    case priv(String)
    case hex(String)
    case nip05(String)

    var is_pub: Bool {
        if case .pub = self {
            return true
        }

        if case .nip05 = self {
            return true
        }
        return false
    }

    var is_hex: Bool {
        if case .hex = self {
            return true
        }
        return false
    }
}

struct LoginView: View {
    @State var key: String = ""
    @State var is_pubkey: Bool = false
    @State var error: String? = nil

    func get_error(parsed_key: ParsedKey?) -> String? {
        if self.error != nil {
            return self.error
        }

        if !key.isEmpty && parsed_key == nil {
            return "Invalid key"
        }

        return nil
    }

    func process_login(_ key: ParsedKey, is_pubkey: Bool) -> Bool {
        switch key {
        case .priv(let priv):
            do {
                try save_privkey(privkey: priv)
            } catch {
                return false
            }
            
            guard let pk = privkey_to_pubkey(privkey: priv) else {
                return false
            }
            save_pubkey(pubkey: pk)

        case .pub(let pub):
            do {
                try clear_saved_privkey()
            } catch {
                return false
            }
            
            save_pubkey(pubkey: pub)

        case .nip05(let id):
            Task.init {
                guard let nip05 = await get_nip05_pubkey(id: id) else {
                    self.error = "Could not fetch pubkey"
                    return
                }

                for relay in nip05.relays {
                    if !(BOOTSTRAP_RELAYS.contains { $0 == relay }) {
                        BOOTSTRAP_RELAYS.append(relay)
                    }
                }
                save_pubkey(pubkey: nip05.pubkey)

                notify(.login, ())
            }


        case .hex(let hexstr):
            if is_pubkey {
                do {
                    try clear_saved_privkey()
                } catch {
                    return false
                }
                
                save_pubkey(pubkey: hexstr)
            } else {
                do {
                    try save_privkey(privkey: hexstr)
                } catch {
                    return false
                }
                
                guard let pk = privkey_to_pubkey(privkey: hexstr) else {
                    return false
                }
                save_pubkey(pubkey: pk)
            }
        }

    notify(.login, ())
    return true
}


    var body: some View {
        ZStack(alignment: .top) {
            DamusGradient()
            VStack {
                Text("Login")
                    .foregroundColor(.white)
                    .font(.title)
                    .padding()

                Text("Enter your account key to login:")
                    .foregroundColor(.white)
                    .padding()

                KeyInput("nsec1...", key: $key)

                let parsed = parse_key(key)

                if parsed?.is_hex ?? false {
                    Text("This is an old-style nostr key. We're not sure if it's a pubkey or private key. Please toggle the button below if this a public key.")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    PubkeySwitch(isOn: $is_pubkey)
                        .padding()
                }

                if let error = get_error(parsed_key: parsed) {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }

                if parsed?.is_pub ?? false {
                    Text("This is a public key, you will not be able to make posts or interact in any way. This is used for viewing accounts from their perspective.")
                        .foregroundColor(.white)
                        .padding()
                }

                if let p = parsed {
                    DamusWhiteButton("Login") {
                        if !process_login(p, is_pubkey: self.is_pubkey) {
                            self.error = "Invalid key"
                        }
                    }
                }
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
    }
}

struct PubkeySwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Toggle(isOn: $isOn) {
                Text("Public Key?")
                    .foregroundColor(.white)
            }
        }
    }
}

func parse_key(_ thekey: String) -> ParsedKey? {
    var key = thekey
    if key.count > 0 && key.first! == "@" {
        key = String(key.dropFirst())
    }

    if hex_decode(key) != nil {
        return .hex(key)
    }

    if (key.contains { $0 == "@" }) {
        return .nip05(key)
    }

    if let bech_key = decode_bech32_key(key) {
        switch bech_key {
        case .pub(let pk):
            return .pub(pk)
        case .sec(let sec):
            return .priv(sec)
        }
    }

    return nil
}

struct NIP05Result: Decodable {
    let names: Dictionary<String, String>
    let relays: Dictionary<String, [String]>?
}

struct NIP05User {
    let pubkey: String
    let relays: [String]
}

func get_nip05_pubkey(id: String) async -> NIP05User? {
    let parts = id.components(separatedBy: "@")

    guard parts.count == 2 else {
        return nil
    }

    let user = parts[0]
    let host = parts[1]

    guard let url = URL(string: "https://\(host)/.well-known/nostr.json?name=\(user)") else {
        return nil
    }

    guard let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url)) else {
        return nil
    }

    guard let json: NIP05Result = decode_data(data) else {
        return nil
    }

    guard let pubkey = json.names[user] else {
        return nil
    }

    var relays: [String] = []
    if let rs = json.relays {
        if let rs = rs[pubkey] {
            relays = rs
        }
    }

    return NIP05User(pubkey: pubkey, relays: relays)
}

struct KeyInput: View {
    let title: String
    let key: Binding<String>

    init(_ title: String, key: Binding<String>) {
        self.title = title
        self.key = key
    }

    var body: some View {
        TextField("", text: key)
            .placeholder(when: key.wrappedValue.isEmpty) {
                Text(title).foregroundColor(.white.opacity(0.6))
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 4.0).opacity(0.2)
            }
            .autocapitalization(.none)
            .foregroundColor(.white)
            .font(.body.monospaced())
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"
        let bech32_pubkey = "KeyInput"
        Group {
            LoginView(key: pubkey)
            LoginView(key: bech32_pubkey)
        }
    }
}
