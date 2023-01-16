//
//  InvoicesView.swift
//  damus
//
//  Created by William Casarin on 2022-10-18.
//

import SwiftUI

struct InvoicesView: View {
    let our_pubkey: String
    var invoices: [Invoice]
    
    @State var open_sheet: Bool = false
    @State var current_invoice: Invoice? = nil
    
    var body: some View {
        TabView {
            ForEach(invoices, id: \.string) { invoice in
                InvoiceView(our_pubkey: our_pubkey, invoice: invoice)
                .tabItem {
                    Text(invoice.string)
                }
                .id(invoice.string)
            }
        }
        .frame(height: 240)
        .tabViewStyle(PageTabViewStyle())
    }
}

struct InvoicesView_Previews: PreviewProvider {
    static var previews: some View {
        InvoicesView(our_pubkey: "", invoices: [Invoice.init(description: .description("description"), amount: .specific(10000), string: "invstr", expiry: 100000, payment_hash: Data(), created_at: 1000000)])
            .frame(width: 300)
    }
}
