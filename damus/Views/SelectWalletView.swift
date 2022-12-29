//
//  SelectWalletView.swift
//  damus
//
//  Created by Suhail Saqan on 12/22/22.
//

import SwiftUI

struct WalletItem: Decodable, Identifiable, Hashable {
    var id: Int
    var name : String
    var link : String
    var appStoreLink : String
    var image: String
}

struct SelectWalletView: View {
    @Binding var showingSelectWallet: Bool
    @Binding var invoice: String
    @Environment(\.openURL) private var openURL
    @State var invoice_copied: Bool = false
    
    let generator = UIImpactFeedbackGenerator(style: .light)
    
    let walletItems = try! JSONDecoder().decode([WalletItem].self, from: Constants.WALLETS)
    
    var body: some View {
        NavigationView {
            let mostRecentWalletName = DamusUserDefaults.mostRecentWalletName
            let recentWalletItem: WalletItem? = walletItems.first(where: { $0.name == mostRecentWalletName })
            let otherWalletItems: [WalletItem] = walletItems.filter { $0.name != mostRecentWalletName }
            
            Form {
                Section("Copy invoice") {
                    HStack {
                        Text(invoice).font(.body)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        
                        Spacer()
                        
                        Image(systemName: self.invoice_copied ? "checkmark.circle" : "doc.on.doc").foregroundColor(.blue)
                    }.clipShape(RoundedRectangle(cornerRadius: 5)).onTapGesture {
                        UIPasteboard.general.string = invoice
                        self.invoice_copied = true
                        generator.impactOccurred()
                    }
                }
                
                if let recentWalletItem = recentWalletItem {
                    Section("Most Recent Wallet") {
                        Button() {
                            if let url = URL(string: "\(recentWalletItem.link)\(invoice)"), UIApplication.shared.canOpenURL(url) {
                                openURL(url)
                            } else {
                                if let url = URL(string: recentWalletItem.appStoreLink), UIApplication.shared.canOpenURL(url) {
                                    openURL(url)
                                }
                            }
                        } label: {
                            HStack {
                                Image(recentWalletItem.image).resizable().frame(width: 32.0, height: 32.0,alignment: .center).cornerRadius(5)
                                Text(recentWalletItem.name).font(.body)
                                Spacer()
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .padding(.vertical, 2.5)
                            .contentShape(Rectangle())
                    }
                }
                
                Section("Other Wallets"){
                    List{
                        ForEach(otherWalletItems, id: \.self) { wallet in
                            Button() {
                                if let url = URL(string: "\(wallet.link)\(invoice)"), UIApplication.shared.canOpenURL(url) {
                                    openURL(url)
                                    DamusUserDefaults.saveMostRecentWallet(name: wallet.name)
                                } else {
                                    if let url = URL(string: wallet.appStoreLink), UIApplication.shared.canOpenURL(url) {
                                        openURL(url)
                                        DamusUserDefaults.saveMostRecentWallet(name: wallet.name)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(wallet.image).resizable().frame(width: 32.0, height: 32.0,alignment: .center).cornerRadius(5)
                                    Text(wallet.name).font(.body)
                                    Spacer()
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 2.5)
                }
            }.navigationBarTitle(Text("Pay the lightning invoice"), displayMode: .inline).navigationBarItems(trailing: Button(action: {
                self.showingSelectWallet = false
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
        SelectWalletView(showingSelectWallet: $show, invoice: $invoice)
    }
}
