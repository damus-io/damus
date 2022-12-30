//
//  InvoiceView.swift
//  damus
//
//  Created by William Casarin on 2022-10-18.
//

import SwiftUI

struct InvoiceView: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    let invoice: Invoice
    @State var showingSelectWallet: Bool = false
    @State var inv: String = ""
       
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .foregroundColor(.clear)
                .background(LinearGradient(gradient: Gradient(colors: [
                    Color(red: 0.8, green: 0.263, blue: 0.773),
                    Color(red: 0.224, green: 0.302, blue: 0.886)
                ]), startPoint: .topTrailing, endPoint: .bottomLeading))
                .cornerRadius(12)
            
            VStack(alignment: .center, spacing: 12) {
                HStack {
                    Label("", systemImage: "bolt.fill")
                        .foregroundColor(.white)
                    Text("Lightning Invoice")
                        .foregroundColor(.white)
                        .textCase(.uppercase)
                }
                Divider()
                    .opacity(0.25)
                    .overlay(.white)
                Text(invoice.description)
                    .foregroundColor(.white)
                Text("\(invoice.amount / 1000)")
                    .padding(.vertical, -15)
                    .padding(.top,15)
                    .foregroundColor(.white)
                    .font(.largeTitle)
                Text("SATS")
                    .font(.footnote)
                    .padding(.top, 0)
                    .foregroundColor(.white)
                PayButton
                    .zIndex(10.0)
            }
            .cornerRadius(8)
            .padding(.bottom, 35) // Workaround so the carousel doesn't overlap the pay button if multiple invoices.
            .padding(.top, 15)
            .padding(.leading, 15)
            .padding(.trailing, 15)
        }
        .sheet(isPresented: $showingSelectWallet, onDismiss: {showingSelectWallet = false}) {
            SelectWalletView(showingSelectWallet: $showingSelectWallet, invoice: $inv)
        }
    }
    
    var PayButton: some View {
        Button {
            inv = invoice.string
            showingSelectWallet = true
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .foregroundColor(Color.accentColor)
                .overlay {
                    Text("Pay")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .textCase(.uppercase)
                }
        }
        .frame(height: 36)
        //.cornerRadius(8)
        //.background(Color.accentColor)
        //.buttonStyle(.bordered)
        .onTapGesture {
            // Temporary solution so that the "pay" button can be clicked (Yes we need an empty tap gesture)
        }
    }
}

let test_invoice = Invoice(description: "This is a description", amount: 100000, string: "lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r", expiry: 604800, payment_hash: Data(), created_at: 1666139119)

struct InvoiceView_Previews: PreviewProvider {
    static var previews: some View {
        InvoiceView(invoice: test_invoice)
            .frame(width: 300, height: 200)
    }
}
