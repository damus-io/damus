//
//  SelectWalletView.swift
//  damus
//
//  Created by Suhail Saqan on 12/22/22.
//

import SwiftUI

struct SelectWalletView: View {
    @Binding var showingSelectWallet: Bool
    let invoice: String
    @Environment(\.openURL) private var openURL
    @State var invoice_copied: Bool = false
    @EnvironmentObject var user_settings: UserSettingsStore
    
    @State var allWalletModels: [Wallet.Model] = Wallet.allModels
    let generator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        NavigationView {
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
                Section("Select a lightning wallet"){
                    List{
                        Button() {
                            let wallet_model = user_settings.default_wallet.model
                            open_with_wallet(wallet: wallet_model, invoice: invoice)
                        } label: {
                            HStack {
                                Text("Default Wallet").font(.body).foregroundColor(.blue)
                            }
                        }.buttonStyle(.plain)
                        List($allWalletModels) { $wallet in
                            if wallet.index >= 0 {
                                Button() {
                                    open_with_wallet(wallet: wallet, invoice: invoice)
                                } label: {
                                    HStack {
                                        Image(wallet.image).resizable().frame(width: 32.0, height: 32.0,alignment: .center).cornerRadius(5)
                                        Text(wallet.displayName).font(.body)
                                    }
                                }.buttonStyle(.plain)
                            }
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
        SelectWalletView(showingSelectWallet: $show, invoice: "")
    }
}
