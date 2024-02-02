//
//  InvoiceView.swift
//  damus
//
//  Created by William Casarin on 2022-10-18.
//

import SwiftUI

struct InvoiceView: View {
    @Environment(\.colorScheme) var colorScheme
    let our_pubkey: Pubkey
    let invoice: Invoice
    @State var showing_select_wallet: Bool = false
    @State var copied = false
    let settings: UserSettingsStore
    
    var CopyButton: some View {
        Button {
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                copied = false
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            UIPasteboard.general.string = invoice.string
        } label: {
            if !copied {
                Image("copy2")
                    .foregroundColor(.gray)
            } else {
                Image("check-circle")
                    .foregroundColor(DamusColors.green)
            }
        }
    }
    
    var PayButton: some View {
        Button {
            if settings.show_wallet_selector {
                present_sheet(.select_wallet(invoice: invoice.string))
            } else {
                do {
                    try open_with_wallet(wallet: settings.default_wallet.model, invoice: invoice.string)
                }
                catch {
                    present_sheet(.select_wallet(invoice: invoice.string))
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 20, style: .circular)
                .foregroundColor(colorScheme == .light ? .black : .white)
                .overlay {
                    Text("Pay", comment: "Button to pay a Lightning invoice.")
                        .fontWeight(.medium)
                        .foregroundColor(colorScheme == .light ? .white : .black)
                }
        }
        .onTapGesture {
            // Temporary solution so that the "pay" button can be clicked (Yes we need an empty tap gesture)
            print("pay button tap")
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .foregroundColor(.secondary.opacity(0.1))
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("", image: "zap.fill")
                        .foregroundColor(.orange)
                    Text("Lightning Invoice", comment: "Indicates that the view is for paying a Lightning invoice.")
                    Spacer()
                    CopyButton
                }
                Divider()
                Text(invoice.description_string)
                Text(invoice.amount.amount_sats_str())
                    .font(.title)
                PayButton
                    .frame(height: 50)
                    .zIndex(10.0)
            }
            .padding(30)
        }
    }
}

enum OpenWalletError: Error {
    case no_wallet_to_open
    case store_link_invalid
    case system_cannot_open_store_link
}

func open_with_wallet(wallet: Wallet.Model, invoice: String) throws {
    let url = try getUrlToOpen(invoice: invoice, with: wallet)
    this_app.open(url)
}

func getUrlToOpen(invoice: String, with wallet: Wallet.Model) throws(OpenWalletError) -> URL {
    if let url = URL(string: "\(wallet.link)\(invoice)"), this_app.canOpenURL(url) {
        return url
    } else {
        guard let store_link = wallet.appStoreLink else {
            throw .no_wallet_to_open
        }
        
        guard let url = URL(string: store_link) else {
            throw .store_link_invalid
        }
        
        guard this_app.canOpenURL(url) else {
            throw .system_cannot_open_store_link
        }
        
        return url
    }
}


let test_invoice = Invoice(description: .description("this is a description"), amount: .specific(10000), string: "lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r", expiry: 604800, created_at: 1666139119)

struct InvoiceView_Previews: PreviewProvider {
    static var previews: some View {
        InvoiceView(our_pubkey: .empty, invoice: test_invoice, settings: test_damus_state.settings)
            .frame(width: 300, height: 200)
    }
}
