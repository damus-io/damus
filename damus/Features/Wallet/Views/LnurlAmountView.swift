//
//  LnurlAmountView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-06-18
//

import SwiftUI
import Combine

class LnurlAmountModel: ObservableObject {
    @Published var custom_amount: String = "0"
    @Published var custom_amount_sats: Int? = 0
    @Published var processing: Bool = false
    @Published var error: String? = nil
    @Published var invoice: String? = nil
    @Published var zap_amounts: [ZapAmountItem] = []
    
    func set_defaults(settings: UserSettingsStore) {
        let default_amount = settings.default_zap_amount
        custom_amount = String(default_amount)
        custom_amount_sats = default_amount
        zap_amounts = get_zap_amount_items(default_amount)
    }
}

/// Enables the user to enter a Bitcoin amount to be sent. Based on `CustomizeZapView`.
struct LnurlAmountView: View {
    let damus_state: DamusState
    let lnurlString: String
    let onInvoiceFetched: (Invoice) -> Void
    let onCancel: () -> Void
    
    @StateObject var model: LnurlAmountModel = LnurlAmountModel()
    @Environment(\.colorScheme) var colorScheme
    @FocusState var isAmountFocused: Bool
    
    init(damus_state: DamusState, lnurlString: String, onInvoiceFetched: @escaping (Invoice) -> Void, onCancel: @escaping () -> Void) {
        self.damus_state = damus_state
        self.lnurlString = lnurlString
        self.onInvoiceFetched = onInvoiceFetched
        self.onCancel = onCancel
    }
    
    func AmountButton(zapAmountItem: ZapAmountItem) -> some View {
        let isSelected = model.custom_amount_sats == zapAmountItem.amount
        
        return Button(action: {
            model.custom_amount_sats = zapAmountItem.amount
            model.custom_amount = String(zapAmountItem.amount)
        }) {
            let fmt = format_msats_abbrev(Int64(zapAmountItem.amount) * 1000)
            Text(verbatim: "\(zapAmountItem.icon)\n\(fmt)")
                .contentShape(Rectangle())
                .font(.headline)
                .frame(width: 70, height: 70)
                .foregroundColor(DamusColors.adaptableBlack)
                .background(isSelected ? DamusColors.adaptableWhite : DamusColors.adaptableGrey)
                .cornerRadius(15)
                .overlay(RoundedRectangle(cornerRadius: 15)
                    .stroke(DamusColors.purple.opacity(isSelected ? 1.0 : 0.0), lineWidth: 2))
        }
    }
    
    func amount_parts(_ n: Int) -> [ZapAmountItem] {
        var i: Int = -1
        let start = n * 4
        let end = start + 4
        
        return model.zap_amounts.filter { _ in
            i += 1
            return i >= start && i < end
        }
    }
    
    func AmountsPart(n: Int) -> some View {
        HStack(alignment: .center, spacing: 15) {
            ForEach(amount_parts(n)) { entry in
                AmountButton(zapAmountItem: entry)
            }
        }
    }
    
    var AmountGrid: some View {
        VStack {
            AmountsPart(n: 0)
            
            AmountsPart(n: 1)
        }
        .padding(10)
    }
    
    var CustomAmountTextField: some View {
        VStack(alignment: .center, spacing: 0) {
            TextField("", text: $model.custom_amount)
                .focused($isAmountFocused)
                .task {
                    self.isAmountFocused = true
                }
                .font(.system(size: 72, weight: .heavy))
                .minimumScaleFactor(0.01)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .onChange(of: model.custom_amount) { newValue in
                    if let parsed = handle_string_amount(new_value: newValue) {
                        model.custom_amount = parsed.formatted()
                        model.custom_amount_sats = parsed
                    } else {
                        model.custom_amount = "0"
                        model.custom_amount_sats = nil
                    }
                }
            let noun = pluralizedString(key: "sats", count: model.custom_amount_sats ?? 0)
            Text(noun)
                .font(.system(size: 18, weight: .heavy))
        }
    }
    
    func fetchInvoice() {
        guard let amount = model.custom_amount_sats, amount > 0 else {
            model.error = NSLocalizedString("Please enter a valid amount", comment: "Error message when no valid amount is entered for LNURL payment")
            return
        }
        
        model.processing = true
        model.error = nil
        
        Task { @MainActor in
            // For LNURL payments without zaps, we use nil for zapreq and comment
            // We just need the invoice for payment
            let msats = Int64(amount) * 1000
            
            // First get the payment request from the LNURL
            guard let payreq = await fetch_static_payreq(lnurlString) else {
                model.processing = false
                model.error = NSLocalizedString("Error fetching LNURL payment information", comment: "Error message when LNURL fetch fails")
                return
            }
            
            // Then fetch the invoice with the amount
            guard let invoiceStr = await fetch_zap_invoice(payreq, zapreq: nil, msats: msats, zap_type: .non_zap, comment: nil) else {
                model.processing = false
                model.error = NSLocalizedString("Error fetching lightning invoice", comment: "Error message when there was an error fetching a lightning invoice")
                return
            }
            
            // Decode the invoice to validate it
            guard let invoice = decode_bolt11(invoiceStr) else {
                model.processing = false
                model.error = NSLocalizedString("Invalid lightning invoice received", comment: "Error message when the lightning invoice received from LNURL is invalid")
                return
            }
            
            // All good, pass the invoice back to the parent view
            model.processing = false
            onInvoiceFetched(invoice)
        }
    }
    
    var PayButton: some View {
        VStack {
            if model.processing {
                Text("Processing...", comment: "Text to indicate that the app is in the process of fetching an invoice.")
                    .padding()
                ProgressView()
            } else {
                Button(action: {
                    fetchInvoice()
                }) {
                    HStack {
                        Text("Continue", comment: "Button to proceed with LNURL payment process.")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(model.custom_amount_sats == 0 || model.custom_amount == "0")
                .opacity(model.custom_amount_sats == 0 || model.custom_amount == "0" ? 0.5 : 1.0)
                .padding(10)
            }
            
            if let error = model.error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }
    
    var CancelButton: some View {
        Button(action: onCancel) {
            HStack {
                Text("Cancel", comment: "Button to cancel the LNURL payment process.")
                    .font(.headline)
                    .padding()
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(NeutralButtonStyle())
        .padding()
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            ScrollView {
                VStack {
                    Text("Enter Amount", comment: "Header text for LNURL payment amount entry screen")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding()
                    
                    Text("How much would you like to send?", comment: "Instruction text for LNURL payment amount")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                    
                    CustomAmountTextField
                    
                    AmountGrid
                    
                    PayButton
                    
                    CancelButton
                }
            }
        }
        .onAppear {
            model.set_defaults(settings: damus_state.settings)
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
}

struct LnurlAmountView_Previews: PreviewProvider {
    static var previews: some View {
        LnurlAmountView(
            damus_state: test_damus_state,
            lnurlString: "lnurl1dp68gurn8ghj7um9wfmxjcm99e3k7mf0v9cxj0m385ekvcenxc6r2c35xvukxefcv5mkvv34x5ekzd3ev56nyd3hxqurzepexejxxepnxscrvwfnv9nxzcn9xq6xyefhvgcxxcmyxymnserxfq5fns",
            onInvoiceFetched: { _ in },
            onCancel: {}
        )
        .frame(width: 400, height: 600)
    }
}
