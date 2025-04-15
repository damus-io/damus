//
//  ConnectWalletView.swift
//  damus
//
//  Created by William Casarin on 2023-05-05.
//

import SwiftUI

struct ConnectWalletView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: WalletModel
    
    @State var scanning: Bool = false
    @State private var showAlert = false
    @State var error: String? = nil
    @State var wallet_scan_result: WalletScanResult = .scanning
    @State var show_introduction: Bool = true
    @State var show_coinos_options: Bool = false
    var nav: NavigationCoordinator
    let userKeypair: Keypair
    
    var body: some View {
        MainContent
            .navigationTitle(NSLocalizedString("Wallet", comment: "Navigation title for attaching Nostr Wallet Connect lightning wallet."))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: wallet_scan_result) { res in
                scanning = false
                
                switch res {
                case .success(let url):
                    error = nil
                    self.model.new(url)
                    
                case .failed:
                    showAlert.toggle()
                
                case .scanning:
                    error = nil
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Invalid Nostr wallet connection string", comment: "Error message when an invalid Nostr wallet connection string is provided."),
                    message: Text("Make sure the wallet you are connecting to supports NWC.", comment: "Hint message when an invalid Nostr wallet connection string is provided."),
                    dismissButton: .default(Text("OK", comment: "Button label indicating user wants to proceed.")) {
                        wallet_scan_result = .scanning
                    }
                )
            }
    }
    
    struct AreYouSure: View {
        let nwc: WalletConnectURL
        @Binding var show_introduction: Bool
        @ObservedObject var model: WalletModel
        
        var body: some View {
            ScrollView {
                VStack(spacing: 25) {
                    
                    Text("Setup Wallet", comment: "Heading for wallet setup confirmation screen")
                        .font(.veryLargeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                    
                    ConnectGraphic
                    
                    Spacer()
                    
                    NWCSettings.AccountDetailsView(nwc: nwc)
                    
                    Spacer()
                    
                    Button(action: {
                        model.connect(nwc)
                        show_introduction = false
                    }) {
                        HStack {
                            Text("Connect", comment: "Text for button to conect to Nostr Wallet Connect lightning wallet.")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 18, alignment: .center)
                    }
                    .buttonStyle(GradientButtonStyle())
                    
                    Button(action: {
                        model.cancel()
                        show_introduction = true
                    }) {
                        HStack {
                            Text("Cancel", comment: "Text for button to cancel out of connecting Nostr Wallet Connect lightning wallet.")
                                .padding()
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(NeutralButtonStyle())
                }
                .padding(.bottom, 50)
                .padding()
            }
        }
        
        var ConnectGraphic: some View {
            HStack(spacing: 0) {
                Button(action: {}, label: {
                    Image("damus-home")
                        .resizable()
                        .frame(width: 30, height: 30)
                })
                .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15), cornerRadius: 9999))
                .disabled(true)
                .padding(.horizontal, 30)
                
                Image("chevron-double-right")
                    .resizable()
                    .frame(width: 25, height: 25)
                
                Button(action: {}, label: {
                    Image("wallet")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundStyle(LINEAR_GRADIENT)
                })
                .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15), cornerRadius: 9999))
                .disabled(true)
                .padding(.horizontal, 30)
            }
        }
    }
    
    var AutomaticSetup: some View {
        VStack(spacing: 10) {
            Text("AUTOMATIC SETUP", comment: "Heading for the section that performs an automatic wallet connection setup.")
                .font(.caption)
                .padding(.top)
                .foregroundStyle(PinkGradient)
            
            Text("Create new wallet", comment: "Button text for creating a new wallet.")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Easily create a new wallet and attach it to your account.", comment: "Description for the create new wallet feature.")
                .font(.body)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            CoinosButton() {
                self.show_coinos_options = true
            }
            .padding()
        }
        .frame(minHeight: 250)
        .padding(10)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(DamusColors.neutral3, lineWidth: 2)
                .padding(2) // Avoids border clipping on the sides
        )
        .padding(.top, 20)
        .sheet(isPresented: $show_coinos_options, content: {
            CoinosConnectionOptionsSheet
        })
    }
    
    var CoinosConnectionOptionsSheet: some View {
        VStack(spacing: 20) {
            Text("How would you like to connect to your Coinos wallet?", comment: "Question for the user when connecting a Coinos wallet.")
                .font(.title3)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
                .lineLimit(2)
            
            Spacer()
            
            VStack(spacing: 5) {
                Button(
                    action: { self.oneClickSetup() },
                    label: {
                        HStack {
                            Spacer()
                            VStack {
                                HStack {
                                    Image(systemName: "wand.and.sparkles")
                                    Text("One-click setup", comment: "Button label for users to do a one-click Coinos wallet setup.")
                                }
                                // I have to hide this on npub logins, because otherwise SwiftUI will start truncating text
                                if self.userKeypair.privkey != nil {
                                    Text("Also click here if you had a one-click setup before.", comment: "Button description hint for users who may want to do a one-click setup.")
                                        .font(.caption)
                                }
                            }
                            Spacer()
                        }
                    }
                )
                .frame(maxWidth: .infinity)
                .buttonStyle(GradientButtonStyle())
                .opacity(self.userKeypair.privkey == nil ? 0.5 : 1.0)
                .disabled(self.userKeypair.privkey == nil)
                
                if self.userKeypair.privkey == nil {
                    Text("You must be logged in with your nsec to use this option.", comment: "Warning text for users who cannot create a Coinos account via the one-click setup without being logged in with their nsec.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    
                    Text("Your profile will not be shared with Coinos.", comment: "Label text for users to reassure them that their nsec is not shared with a third party.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            
            Button(
                action: {
                    show_introduction = false
                    show_coinos_options = false
                    openURL(URL(string:"https://coinos.io/settings/nostr")!)
                },
                label: {
                    HStack {
                        Spacer()
                        
                        VStack {
                            HStack {
                                Image(systemName: "arrow.up.right")
                                Text("Connect via the website", comment: "Button label for users who are setting up a Coinos wallet and would like to connect via the website")
                            }
                            Text("Click here if you have a Coinos username and password.", comment: "Button description hint for users who may want to connect via the website.")
                                .font(.caption)
                        }
                        
                        Spacer()
                    }
                }
            )
            .frame(maxWidth: .infinity)
        }
        .padding()
        .presentationDetents([.height(300)])
    }
    
    func oneClickSetup() {
        Task {
            show_coinos_options = false
            do {
                guard let fullKeypair = self.userKeypair.to_full() else {
                    throw CoinosDeterministicAccountClient.ClientError.errorFormingRequest
                }
                let client = CoinosDeterministicAccountClient(userKeypair: fullKeypair)
                try await client.loginOrRegister()
                let nwcURL = try await client.createNWCConnection()
                model.connect(nwcURL)   // Connect directly, to make it a true one-click setup
            }
            catch {
                present_sheet(.error(.init(
                    user_visible_description: NSLocalizedString("Something went wrong when performing the one-click Coinos wallet setup.", comment: "Error label when user tries the one-click Coinos wallet setup but fails for some generic reason."),
                    tip: NSLocalizedString("Check your internet connection and try again. If the error persists, contact support.", comment: "Error tip when user tries to create the one-click Coinos wallet setup but fails for a generic reason."),
                    technical_info: error.localizedDescription
                )))
            }
        }
    }
    
    var ManualSetup: some View {
        VStack(spacing: 10) {
            Text("MANUAL SETUP", comment: "Label for manual wallet setup.")
                .font(.caption)
                .padding(.top)
                .foregroundStyle(PinkGradient)
            
            Text("Use existing", comment: "Button text to use an existing wallet.")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Attach to any third party provider you already use.", comment: "Information text guiding users on attaching existing provider.")
                .font(.body)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button(action: {
                if let pasted_nwc = UIPasteboard.general.string {
                    guard let url = WalletConnectURL(str: pasted_nwc) else {
                        wallet_scan_result = .failed
                        return
                    }
                    
                    wallet_scan_result = .success(url)
                }
            }) {
                HStack {
                    Image("clipboard")
                    Text("Paste NWC Address", comment: "Text for button to connect a lightning wallet.")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 250, maxWidth: .infinity, maxHeight: 15, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
            .padding(.horizontal)
            
            Button(action: {
                nav.push(route: Route.WalletScanner(result: $wallet_scan_result))
            }) {
                HStack {
                    Image("qr-code")
                    Text("Scan NWC Address", comment: "Text for button to connect a lightning wallet.")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 250, maxWidth: .infinity, maxHeight: 15, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(minHeight: 300)
        .padding(10)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(DamusColors.neutral3, lineWidth: 2)
                .padding(2) // Avoids border clipping on the sides
        )
        .padding(.top, 20)
    }
    
    var ConnectWallet: some View {
        ScrollView {
            VStack(spacing: 25) {
                
                Text("Setup Wallet", comment: "Heading for Nostr Wallet Connect setup screen")
                    .font(.veryLargeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                AutomaticSetup
                
                ManualSetup
                
                if let err = self.error {
                    Text(err)
                        .foregroundColor(.red)
                }
            }
            .padding(.bottom, 50)
            .padding()
        }
    }
    
    var MainContent: some View {
        Group {
            switch model.connect_state {
            case .new(let nwc):
                AreYouSure(nwc: nwc, show_introduction: $show_introduction, model: self.model)
                    .onAppear() {
                        show_introduction = false
                    }
            case .existing:
                Text(verbatim: "Shouldn't happen")
            case .none:
                ConnectWallet
            }
        }
        .fullScreenCover(isPresented: $show_introduction, content: {
            ZapExplainerView(show_introduction: $show_introduction, nav: nav)
        })
    }
}

struct ConnectWalletView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectWalletView(model: WalletModel(settings: UserSettingsStore()), nav: .init(), userKeypair: test_keypair)
            .previewDisplayName("Main Wallet Connect View")
        ConnectWalletView.AreYouSure(nwc: get_test_nwc(), show_introduction: .constant(false), model: WalletModel(settings: test_damus_state.settings))
            .previewDisplayName("Are you sure screen")
    }
    
    static func get_test_nwc() -> WalletConnectURL {
        let pk = "9d088f4760422443d4699b485e2ac66e565a2f5da1198c55ddc5679458e3f67a"
        let sec = "ff2eefd57196d42089e1b42acc39916d7ecac52e0625bd70597bbd5be14aff18"
        let relay = "wss://relay.getalby.com/v1"
        let str = "nostrwalletconnect://\(pk)?relay=\(relay)&secret=\(sec)"
        
        return WalletConnectURL(str: str)!
    }
}
