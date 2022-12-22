//
//  SelectWalletView.swift
//  damus
//
//  Created by Suhail Saqan on 12/22/22.
//

import SwiftUI

struct WalletItem : Decodable, Identifiable {
    var id: Int
    var name : String
    var link : String
    var appStoreLink : String
    var image: String
}

struct SelectWalletView: View {
    @Binding var show_select_wallet: Bool
    @Binding var invoice: String
    @Environment(\.openURL) private var openURL
    
    let walletItems = try! JSONDecoder().decode([WalletItem].self, from: Constants.WALLETS)
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                ForEach(walletItems) { wallet in
                   HStack(spacing: 20) {
                       Image(wallet.image)
                         .resizable()
                         .scaledToFit()
                         .aspectRatio(contentMode: .fit)
                         .cornerRadius(5)
                       Text("\(wallet.name)")
                   }.onTapGesture {
                       if let url = URL(string: "\(wallet.link)\(invoice)"), UIApplication.shared.canOpenURL(url) {
                           openURL(url)
                       } else {
                           if let url = URL(string: wallet.appStoreLink), UIApplication.shared.canOpenURL(url) {
                               openURL(url)
                           }
                       }
                   }
                    Divider()
                }
            }
            .navigationBarTitle(Text("Select Wallet"), displayMode: .inline)
                .navigationBarItems(trailing: Button(action: {
                    self.show_select_wallet = false
                }) {
                    Text("Done").bold()
                })
        }

    }
}

struct SelectWalletView_Previews: PreviewProvider {
    @State static var show: Bool = true
    @State static var invoice: String = ""
    
    static var previews: some View {
        SelectWalletView(show_select_wallet: $show, invoice: $invoice)
    }
}
