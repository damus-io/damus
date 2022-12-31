//
//  InvoiceView.swift
//  damus
//
//  Created by William Casarin on 2022-10-18.
//

import SwiftUI

func open_with_wallet(wallet: Wallet.Model, invoice: String) {
    if let url = URL(string: "\(wallet.link)\(invoice)"), UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url)
    } else {
        if let url = URL(string: wallet.appStoreLink), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

struct InvoiceView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL
    
    let invoice: Invoice
    @State var showing_select_wallet: Bool = false
    @ObservedObject var user_settings = UserSettingsStore()
    
    var PayButton: some View {
        Button {
            if user_settings.show_wallet_selector {
                showing_select_wallet = true
            } else {
                open_with_wallet(wallet: user_settings.default_wallet.model, invoice: invoice.string)
            }
        } label: {
            RoundedRectangle(cornerRadius: 20)
                .foregroundColor(colorScheme == .light ? .black : .white)
                .overlay {
                    Text("Pay")
                        .fontWeight(.medium)
                        .foregroundColor(colorScheme == .light ? .white : .black)
                }
        }
        //.buttonStyle(.bordered)
        .onTapGesture {
            // Temporary solution so that the "pay" button can be clicked (Yes we need an empty tap gesture)
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .foregroundColor(.secondary.opacity(0.1))
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("", systemImage: "bolt.fill")
                        .foregroundColor(.orange)
                    Text("Lightning Invoice")
                }
                Divider()
                Text(invoice.description)
                Text("\(invoice.amount / 1000) sats")
                    .font(.title)
                PayButton
                    .frame(height: 50)
                    .zIndex(10.0)
            }
            .padding(30)
        }
        .sheet(isPresented: $showing_select_wallet, onDismiss: {showing_select_wallet = false}) {
            SelectWalletView(showingSelectWallet: $showing_select_wallet, invoice: invoice.string).environmentObject(user_settings)
        }
    }
}

let test_invoice = Invoice(description: "this is a description", amount: 10000, string: "lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r", expiry: 604800, payment_hash: Data(), created_at: 1666139119)

struct InvoiceView_Previews: PreviewProvider {
    static var previews: some View {
        InvoiceView(invoice: test_invoice)
            .frame(width: 200, height: 200)
    }
}
