//
//  LoginView.swift
//  damus
//
//  Created by William Casarin on 2022-05-22.
//

import CodeScanner
import SwiftUI

enum ParsedKey {
    case pub(Pubkey)
    case priv(Privkey)
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

    var is_priv: Bool {
        if case .priv = self {
            return true
        }
        return false
    }
}

struct LoginView: View {
    @State var key: String = ""
    @State var is_pubkey: Bool = false
    @State var error: String? = nil
    @State private var credential_handler = CredentialHandler()
    @State private var shouldSaveKey: Bool = true
    var nav: NavigationCoordinator

    func get_error(parsed_key: ParsedKey?) -> String? {
        if self.error != nil {
            return self.error
        }

        if !key.isEmpty && parsed_key == nil {
            return LoginError.invalid_key.errorDescription
        }

        return nil
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                Spacer()
                
                SignInHeader()
                
                SignInEntry(key: $key, shouldSaveKey: $shouldSaveKey)
                
                let parsed = parse_key(key)
                
                if parsed?.is_hex ?? false {
                    // convert to bech32 here
                }

                if let error = get_error(parsed_key: parsed) {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }

                if parsed?.is_pub ?? false {
                    Text("This is a public key, you will not be able to make notes or interact in any way. This is used for viewing accounts from their perspective.", comment: "Warning that the inputted account key is a public key and the result of what happens because of it.")
                        .foregroundColor(Color.orange)
                        .bold()
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let p = parsed {
                    Button(action: {
                        Task {
                            do {
                                try await process_login(p, is_pubkey: is_pubkey, shouldSaveKey: shouldSaveKey)
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }) {
                        HStack {
                            Text("Login", comment:  "Button to log into account.")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 12, alignment: .center)
                    }
                    .accessibilityIdentifier(AppAccessibilityIdentifiers.sign_in_confirm_button.rawValue)
                    .buttonStyle(GradientButtonStyle())
                    .padding(.top, 10)
                }

                CreateAccountPrompt(nav: nav)
                    .padding(.top, 10)

                Spacer()
            }
            .padding()
            .padding(.bottom, 50)
        }
        .background(DamusBackground(maxHeight: UIScreen.main.bounds.size.height/2), alignment: .top)
        .onAppear {
            credential_handler.check_credentials()
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
    }
}

extension View {
    func nsecLoginStyle(key: String, title: String) -> some View {
        self
            .placeholder(when: key.isEmpty) {
                Text(title).foregroundColor(.white.opacity(0.6))
            }
            .padding(10)
            .autocapitalization(.none)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .font(.body.monospaced())
            .textContentType(.password)
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
        case .pub(let pk):  return .pub(pk)
        case .sec(let sec): return .priv(sec)
        }
    }

    return nil
}

enum LoginError: LocalizedError {
    case invalid_key
    case nip05_failed
    
    var errorDescription: String? {
        switch self {
        case .invalid_key:
            return NSLocalizedString("Invalid key", comment: "Error message indicating that an invalid account key was entered for login.")
        case .nip05_failed:
            return "Could not fetch pubkey"
        }
    }
}

func process_login(_ key: ParsedKey, is_pubkey: Bool, shouldSaveKey: Bool = true) async throws {
    if shouldSaveKey {
        switch key {
        case .priv(let priv):
            try handle_privkey(priv)
        case .pub(let pub):
            try clear_saved_privkey()
            save_pubkey(pubkey: pub)

        case .nip05(let id):
            guard let nip05 = await get_nip05_pubkey(id: id) else {
                throw LoginError.nip05_failed
            }

            // this is a weird way to login anyways
            /*
             var bootstrap_relays = load_bootstrap_relays(pubkey: nip05.pubkey)
             for relay in nip05.relays {
             if !(bootstrap_relays.contains { $0 == relay }) {
             bootstrap_relays.append(relay)
             }
             }
             */
            save_pubkey(pubkey: nip05.pubkey)

        case .hex(let hexstr):
            if is_pubkey, let pubkey = hex_decode_pubkey(hexstr) {
                try clear_saved_privkey()

                save_pubkey(pubkey: pubkey)
            } else if let privkey = hex_decode_privkey(hexstr) {
                try handle_privkey(privkey)
            }
        }
    }
    
    func handle_privkey(_ privkey: Privkey) throws {
        try save_privkey(privkey: privkey)
        
        guard let pk = privkey_to_pubkey(privkey: privkey) else {
            throw LoginError.invalid_key
        }

        CredentialHandler().save_credential(pubkey: pk, privkey: privkey)
        save_pubkey(pubkey: pk)
    }

    func handle_transient_privkey(_ key: ParsedKey) -> Keypair? {
        if case let .priv(priv) = key, let pubkey = privkey_to_pubkey(privkey: priv) {
            return Keypair(pubkey: pubkey, privkey: priv)
        }
        return nil
    }

    let keypair = shouldSaveKey ? get_saved_keypair() : handle_transient_privkey(key)

    guard let keypair = keypair else {
        return
    }

    await MainActor.run {
        notify(.login(keypair))
    }
}

struct NIP05Result: Decodable {
    let names: Dictionary<String, String>
    let relays: Dictionary<String, [String]>?
}

struct NIP05User {
    let pubkey: Pubkey
    //let relays: [String]
}

func get_nip05_pubkey(id: String) async -> NIP05User? {
    let parts = id.components(separatedBy: "@")

    guard parts.count == 2 else {
        return nil
    }

    let user = parts[0]
    let host = parts[1]

    guard let url = URL(string: "https://\(host)/.well-known/nostr.json?name=\(user)"),
          let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url)),
          let json: NIP05Result = decode_data(data),
          let pubkey_hex = json.names[user],
          let pubkey = hex_decode_pubkey(pubkey_hex)
    else {
        return nil
    }

    /*
    var relays: [String] = []

    if let rs = json.relays, let rs = rs[pubkey] {
        relays = rs
    }
     */

    return NIP05User(pubkey: pubkey/*, relays: relays*/)
}

struct KeyInput: View {
    let title: String
    let key: Binding<String>
    let shouldSaveKey: Binding<Bool>
    var privKeyFound: Binding<Bool>
    @State private var is_secured: Bool = true

    init(_ title: String, key: Binding<String>, shouldSaveKey: Binding<Bool>, privKeyFound: Binding<Bool>) {
        self.title = title
        self.key = key
        self.shouldSaveKey = shouldSaveKey
        self.privKeyFound = privKeyFound
    }

    var body: some View {
        HStack {
            Button(action: {
                if let pastedkey = UIPasteboard.general.string {
                    self.key.wrappedValue = pastedkey
                }
            }, label: {
                Image(systemName: "doc.on.clipboard")
            })
            .foregroundColor(.gray)
            .accessibilityLabel(NSLocalizedString("Paste private key", comment: "Accessibility label for the private key paste button"))
            
            SignInScan(shouldSaveKey: shouldSaveKey, loginKey: key, privKeyFound: privKeyFound)

            if is_secured  {
                 SecureField("", text: key)
                     .nsecLoginStyle(key: key.wrappedValue, title: title)
                     .accessibilityLabel(NSLocalizedString("Account private key", comment: "Accessibility label for the private key input field"))
             } else {
                 TextField("", text: key)
                     .nsecLoginStyle(key: key.wrappedValue, title: title)
                     .accessibilityLabel(NSLocalizedString("Account private key", comment: "Accessibility label for the private key input field"))
             }
            
            Button(action: {
                is_secured.toggle()
            }, label: {
                Image(systemName: "eye.slash")
            })
            .foregroundColor(.gray)
            .accessibilityLabel(NSLocalizedString("Toggle key visibility", comment: "Accessibility label for toggling the visibility of the private key input field"))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.gray, lineWidth: 1)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .foregroundColor(.damusAdaptableWhite)
                }
        }
    }
}

struct SignInHeader: View {
    var body: some View {
        VStack {
            Image("logo-nobg")
                .resizable()
                .frame(width: 56, height: 56, alignment: .center)
                .shadow(color: DamusColors.purple, radius: 2)
                .padding(.bottom)
                .accessibilityLabel(NSLocalizedString("Damus logo", comment: "Accessibility label for damus logo"))
            
            Text("Sign in", comment: "Title of view to log into an account.")
                .foregroundColor(DamusColors.neutral6)
                .font(.system(size: 32, weight: .bold))
                .padding(.bottom, 5)
            
            Text("Welcome to the social network you control", comment: "Welcome text")
                .foregroundColor(DamusColors.neutral6)
        }
    }
}

struct SignInEntry: View {
    let key: Binding<String>
    let shouldSaveKey: Binding<Bool>
    @State private var privKeyFound: Bool = false
    var body: some View {
        VStack(alignment: .leading) {
            Text("Enter your account key", comment: "Prompt for user to enter an account key to login.")
                .foregroundColor(DamusColors.neutral6)
                .fontWeight(.medium)
                .padding(.top, 30)
            
            KeyInput(NSLocalizedString("nsec1…", comment: "Prompt for user to enter in an account key to login. This text shows the characters the key could start with if it was a private key."),
                     key: key,
                     shouldSaveKey: shouldSaveKey,
                     privKeyFound: $privKeyFound)
            .accessibilityIdentifier(AppAccessibilityIdentifiers.sign_in_nsec_key_entry_field.rawValue)
            
            if privKeyFound {
                Toggle(NSLocalizedString("Save Key in Secure Keychain", comment: "Toggle to save private key to the Apple secure keychain."), isOn: shouldSaveKey)
            }
        }
    }
}

struct SignInScan: View {
    @State var showQR: Bool = false
    @State var qrkey: ParsedKey?
    @Binding var shouldSaveKey: Bool
    @Binding var loginKey: String
    @Binding var privKeyFound: Bool
    let generator = UINotificationFeedbackGenerator()

    var body: some View {
        VStack {
            Button(action: { showQR.toggle() }, label: {
                Image(systemName: "qrcode.viewfinder")})
            .foregroundColor(.gray)
            .accessibilityLabel(NSLocalizedString("Scan QR code", comment: "Accessibility label for a button that scans a private key QR code"))
        }
        .sheet(isPresented: $showQR, onDismiss: {
            if qrkey == nil { resetView() }}
        ) {
            QRScanNSECView(showQR: $showQR,
                           privKeyFound: $privKeyFound,
                           codeScannerCompletion: { scannerCompletion($0) })
        }
        .onChange(of: showQR) { show in
            if showQR { resetView() }
        }
    }

    func handleQRString(_ string: String) {
        qrkey = parse_key(string)
        if let key = qrkey, key.is_priv {
            loginKey = string
            privKeyFound = true
            shouldSaveKey = false
            generator.notificationOccurred(.success)
        }
    }

    func scannerCompletion(_ result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let success):
            handleQRString(success.string)
        case .failure:
            return
        }
    }

    func resetView() {
        loginKey = ""
        qrkey = nil
        privKeyFound = false
        shouldSaveKey = true
    }
}

struct CreateAccountPrompt: View {
    var nav: NavigationCoordinator
    var body: some View {
        HStack {
            Text("New to Nostr?", comment: "Ask the user if they are new to Nostr")
                .foregroundColor(Color("DamusMediumGrey"))
            
            Button(NSLocalizedString("Create account", comment: "Button to navigate to create account view.")) {
                nav.push(route: Route.CreateAccount)
            }
            .accessibilityIdentifier(AppAccessibilityIdentifiers.sign_up_option_button.rawValue)
            
            Spacer()
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
//        let pubkey = "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"
        let pubkey = "npub18m76awca3y37hkvuneavuw6pjj4525fw90necxmadrvjg0sdy6qsngq955"
        let bech32_pubkey = "KeyInput"
        Group {
            LoginView(key: pubkey, nav: .init())
                .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
            LoginView(key: bech32_pubkey, nav: .init())
                .previewDevice(PreviewDevice(rawValue: "iPhone 15 Pro Max"))
        }
    }
}
