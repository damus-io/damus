//
//  InvoicesView.swift
//  damus
//
//  Created by William Casarin on 2022-10-18.
//

import SwiftUI

struct InvoicesView: View {
    var invoices: [Invoice]
    
    @State var open_sheet: Bool = false
    @State var current_invoice: Invoice? = nil
    
    var body: some View {
        TabView {
            ForEach(invoices, id: \.string) { invoice in
                InvoiceView(invoice: invoice)
                .tabItem {
                    Text(invoice.string)
                }
                .id(invoice.string)
            }
        }
        .frame(height:250)
        .tabViewStyle(PageTabViewStyle())
    }
}

struct InvoicesView_Previews: PreviewProvider {
    // TODO: Unclear why invoices 2 and 3 details aren't showing correctly.
    static var mockInvoices = [
        Invoice(description: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed porta nisl vel aliquet ultricies. Mauris mollis dictum nulla ac posuere. Aliquam euismod ligula at metus vestibulum suscipit sed non tortor.", amount: 100000000, string: "invstr", expiry: 100000, payment_hash: Data(), created_at: 1000000),
        Invoice(description: "Lorem ipsum dolor sit amet", amount: 1000, string: "invstr", expiry: 100000, payment_hash: Data(), created_at: 1000000),
        Invoice(description: "Dolor sit amet", amount: 500000, string: "invstr", expiry: 100000, payment_hash: Data(), created_at: 1000000)
    ]
        
    static var previews: some View {
        InvoicesView(invoices : mockInvoices)
    }
}
