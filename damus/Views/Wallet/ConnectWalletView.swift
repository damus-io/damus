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
    var nav: NavigationCoordinator
    
    var body: some View {
        MainContent
            .navigationTitle(NSLocalizedString("Wallet", comment: "Navigation title for attaching Nostr Wallet Connect lightning wallet."))
            .navigationBarTitleDisplayMode(.inline)
            .padding()
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
    
    func AreYouSure(nwc: WalletConnectURL) -> some View {
        VStack(spacing: 25) {

            Text("Are you sure you want to connect this wallet?", comment: "Prompt to ask user if they want to attach their Nostr Wallet Connect lightning wallet.")
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(nwc.relay.absoluteString)
                .font(.body)
                .foregroundColor(.gray)

            if let lud16 = nwc.lud16 {
                Text(lud16)
                    .font(.body)
                    .foregroundColor(.gray)
            }
            
            Button(action: {
                model.connect(nwc)
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
            }) {
                HStack {
                    Text("Cancel", comment: "Text for button to cancel out of connecting Nostr Wallet Connect lightning wallet.")
                        .padding()
                }
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(NeutralButtonStyle())
        }
    }
    
    var ConnectWallet: some View {
        VStack(spacing: 25) {
            
            AlbyButton() {
                openURL(URL(string:"https://nwc.getalby.com/apps/new?c=Damus")!)
            }
            
            //
            // Mutiny Wallet NWC is way too advanced to recommend for normal
            // users until they have a way to do async receive.
            //

            /*
            MutinyButton() {
                openURL(URL(string:"https://app.mutinywallet.com/settings/connections?callbackUri=nostr%2bwalletconnect&name=Damus")!)
            }
            */
            
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
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 18, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
            
            Button(action: {
                nav.push(route: Route.WalletScanner(result: $wallet_scan_result))
            }) {
                HStack {
                    Image("qr-code")
                    Text("Scan NWC Address", comment: "Text for button to connect a lightning wallet.")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 18, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())

            
            if let err = self.error {
                Text(err)
                    .foregroundColor(.red)
            }
        }
    }
    
    var TopSection: some View {
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
    
    var TitleSection: some View {
        VStack(spacing: 25) {
            Text("Damus Wallet", comment: "Title text for Damus Wallet view.")
                .fontWeight(.bold)
            
            Text("Securely connect your Damus app to your wallet using Nostr\u{00A0}Wallet\u{00A0}Connect", comment: "Text to prompt user to connect their wallet using 'Nostr Wallet Connect'.")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }
    
    var MainContent: some View {
        Group {
            TopSection
            switch model.connect_state {
            case .new(let nwc):
                AreYouSure(nwc: nwc)
            case .existing:
                Text(verbatim: "Shouldn't happen")
            case .none:
                TitleSection
                ConnectWallet
            }
        }
    }
}

struct ConnectWalletView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectWalletView(model: WalletModel(settings: UserSettingsStore()), nav: .init())
    }
}
