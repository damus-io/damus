//
//  InvoicesView.swift
//  damus
//
//  Created by William Casarin on 2022-10-18.
//

import SwiftUI

struct InvoicesView: View {
    let our_pubkey: Pubkey
    var invoices: [Invoice]
    let settings: UserSettingsStore
    
    var body: some View {
        TabView {
            ForEach(invoices, id: \.string) { invoice in
                InvoiceView(our_pubkey: our_pubkey, invoice: invoice, settings: settings)
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
        InvoicesView(our_pubkey: test_note.pubkey, invoices: [Invoice.init(description: .description("description"), amount: .specific(10000), string: "invstr", expiry: 100000, created_at: 1000000)], settings: test_damus_state.settings)
            .frame(width: 300)
    }
}
