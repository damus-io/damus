//
//  WalletView.swift
//  damus
//
//  Created by William Casarin on 2023-05-05.
//

import SwiftUI

struct WalletView: View {
    @ObservedObject var model: WalletModel
    
    func MainWalletView(nwc: WalletConnectURL) -> some View {
        VStack {
            Text("\(nwc.relay.id)")
            
            BigButton("Disconnect Wallet") {
                self.model.disconnect()
            }
        }
        .padding()
    }
    
    var body: some View {
        switch model.connect_state {
        case .new:
            ConnectWalletView(model: model)
        case .none:
            ConnectWalletView(model: model)
        case .existing(let nwc):
            MainWalletView(nwc: nwc)
        }
    }
}

struct WalletView_Previews: PreviewProvider {
    static var previews: some View {
        WalletView(model: WalletModel())
    }
}
