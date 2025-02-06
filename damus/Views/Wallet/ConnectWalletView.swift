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
    var nav: NavigationCoordinator
    
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
                show_introduction = false
                openURL(URL(string:"https://coinos.io/settings/nostr")!)
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
        ConnectWalletView(model: WalletModel(settings: UserSettingsStore()), nav: .init())
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
