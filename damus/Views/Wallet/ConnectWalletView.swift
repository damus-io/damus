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
    @State var error: String? = nil
    @State var wallet_scan_result: WalletScanResult = .scanning
    var nav: NavigationCoordinator
    
    var body: some View {
        MainContent
            .navigationTitle(NSLocalizedString("Attach a Wallet", comment: "Navigation title for attaching Nostr Wallet Connect lightning wallet."))
            .navigationBarTitleDisplayMode(.large)
            .padding()
            .onChange(of: wallet_scan_result) { res in
                scanning = false
                
                switch res {
                case .success(let url):
                    error = nil
                    self.model.new(url)
                    
                case .failed:
                    error = NSLocalizedString("Invalid Nostr wallet connection string", comment: "Error message when an invalid Nostr wallet connection string is provided.")
                
                case .scanning:
                    error = nil
                }
            }
    }
    
    func AreYouSure(nwc: WalletConnectURL) -> some View {
        VStack {
            Text("Are you sure you want to attach this wallet?", comment: "Prompt to ask user if they want to attach their Nostr Wallet Connect lightning wallet.")
                .font(.title)
            
            Text(nwc.relay.id)
                .font(.body)
                .foregroundColor(.gray)
            
            if let lud16 = nwc.lud16 {
                Text(lud16)
                    .font(.body)
                    .foregroundColor(.gray)
            }
            
            BigButton(NSLocalizedString("Attach", comment: "Text for button to attach Nostr Wallet Connect lightning wallet.")) {
                model.connect(nwc)
            }
            
            BigButton(NSLocalizedString("Cancel", comment: "Text for button to cancel out of connecting Nostr Wallet Connect lightning ewallet.")) {
                model.cancel()
            }
        }
    }
    
    var ConnectWallet: some View {
        VStack {            
            AlbyButton() {
                openURL(URL(string:"https://nwc.getalby.com/apps/new?c=Damus")!)
            }
            
            BigButton(NSLocalizedString("Attach Wallet", comment: "Text for button to attach Nostr Wallet Connect lightning wallet.")) {
                nav.push(route: Route.WalletScanner(result: $wallet_scan_result))
            }
            
            if let err = self.error {
                Text(err)
                    .foregroundColor(.red)
            }
        }
    }
    
    var MainContent: some View {
        Group {
            switch model.connect_state {
            case .new(let nwc):
                AreYouSure(nwc: nwc)
            case .existing:
                Text(verbatim: "Shouldn't happen")
            case .none:
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
