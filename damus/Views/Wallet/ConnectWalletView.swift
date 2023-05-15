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
    
    var body: some View {
        MainContent
            .navigationTitle("Attach a Wallet")
            .navigationBarTitleDisplayMode(.large)
            .padding()
            .onChange(of: wallet_scan_result) { res in
                scanning = false
                
                switch res {
                case .success(let url):
                    error = nil
                    self.model.new(url)
                    
                case .failed:
                    error = "Invalid nostr wallet connection string"
                
                case .scanning:
                    error = nil
                }
            }
    }
    
    func AreYouSure(nwc: WalletConnectURL) -> some View {
        VStack {
            Text("Are you sure you want to attach this wallet?")
                .font(.title)
            
            Text(nwc.relay.id)
                .font(.body)
                .foregroundColor(.gray)
            
            if let lud16 = nwc.lud16 {
                Text(lud16)
                    .font(.body)
                    .foregroundColor(.gray)
            }
            
            BigButton("Attach") {
                model.connect(nwc)
            }
            
            BigButton("Cancel") {
                model.cancel()
            }
        }
    }
    
    var ConnectWallet: some View {
        VStack {
            NavigationLink(destination: WalletScannerView(result: $wallet_scan_result), isActive: $scanning) {
                EmptyView()
            }
            
            AlbyButton() {
                openURL(URL(string:"https://nwc.getalby.com/apps/new?c=Damus")!)
            }
            
            BigButton("Attach Wallet") {
                scanning = true
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
                Text("Shouldn't happen")
            case .none:
                ConnectWallet
            }
        }
    }
}

struct ConnectWalletView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectWalletView(model: WalletModel(settings: UserSettingsStore()))
    }
}
