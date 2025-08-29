//
//  SendPaymentView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-06-13.
//

import SwiftUI
import CodeScanner

fileprivate let SEND_PAYMENT_TIMEOUT: Duration = .seconds(10)

/// A view that allows a user to pay a lightning invoice
struct SendPaymentView: View {
    
    // MARK: - Helper structures
    
    /// Represents the state of the invoice payment process
    enum SendState {
        case enterInvoice(scannerMessage: String?)
        case confirmPayment(invoice: Invoice)
        case enterLnurlAmount(lnurl: String)
        case processing
        case completed
        case failed(error: HumanReadableError)
    }
    
    typealias HumanReadableError = ErrorView.UserPresentableError
    
    
    // MARK: - Immutable members
    
    let damus_state: DamusState
    let model: WalletModel
    let nwc: WalletConnectURL
    @Environment(\.dismiss) var dismiss
    
    
    // MARK: - State management
    
    @State private var sendState: SendState = .enterInvoice(scannerMessage: nil) {
        didSet {
            switch sendState {
            case .enterInvoice, .confirmPayment, .processing, .enterLnurlAmount:
                break
            case .completed:
                // Refresh wallet to reflect new balance after payment
                Task { await WalletConnect.refresh_wallet_information(damus_state: damus_state) }
            case .failed:
                // Even when a wallet says it has failed, update balance just in case it is a false negative,
                // This might prevent the user from accidentally sending a payment twice in case of a bug.
                Task { await WalletConnect.refresh_wallet_information(damus_state: damus_state) }
            }
        }
    }
    var isShowingScanner: Bool {
        if case .enterInvoice = sendState { true } else { false }
    }
    
    
    // MARK: - Views
    
    var body: some View {
        VStack(alignment: .center) {
            switch sendState {
            case .enterInvoice(let scannerMessage):
                invoiceInputView(scannerMessage: scannerMessage)
                    .padding(40)
            case .confirmPayment(let invoice):
                confirmationView(invoice: invoice)
                    .padding(40)
            case .enterLnurlAmount(let lnurl):
                LnurlAmountView(
                    damus_state: damus_state,
                    lnurlString: lnurl,
                    onInvoiceFetched: { invoice in
                        sendState = .confirmPayment(invoice: invoice)
                    },
                    onCancel: {
                        sendState = .enterInvoice(scannerMessage: nil)
                    }
                )
            case .processing:
                processingView
                    .padding(40)
            case .completed:
                completedView
                    .padding(40)
            case .failed(error: let error):
                failedView(error: error)
            }
        }
    }
    
    func invoiceInputView(scannerMessage: String?) -> some View {
        VStack(spacing: 20) {
            Text("Scan Lightning Invoice", comment: "Title for the invoice scanning screen")
                .font(.title2)
                .bold()
            
            CodeScannerView(
                codeTypes: [.qr],
                scanMode: .continuous,
                showViewfinder: true,   // The scan only seems to work if it fits the bounding box, so let's make this visible to hint that to the users
                simulatedData: "lightning:lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r",
                completion: handleScan
            )
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.accentColor, lineWidth: 2)
            )
            .padding(.horizontal)
            
            VStack(spacing: 15) {
                Button(action: {
                    if let pastedInvoice = getPasteboardContent() {
                        processUserInput(pastedInvoice)
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste from Clipboard", comment: "Button to paste invoice from clipboard")
                    }
                    .frame(minWidth: 250, maxWidth: .infinity, alignment: .center)
                    .padding()
                }
                .buttonStyle(NeutralButtonStyle())
                .accessibilityLabel(NSLocalizedString("Paste invoice from clipboard", comment: "Accessibility label for the invoice paste button"))
            }
            .padding(.horizontal)
            
            if let scannerMessage {
                Text(scannerMessage)
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
    }
    
    func confirmationView(invoice: Invoice) -> some View {
        let insufficientFunds: Bool = (invoice.amount.amount_sats() ?? 0) > (model.balance ?? 0)
        return VStack(spacing: 20) {
            Text("Confirm Payment", comment: "Title for payment confirmation screen")
                .font(.title2)
                .bold()
            
            VStack(spacing: 15) {
                Text("Amount", comment: "Label for invoice payment amount in confirmation screen")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                if case .specific(let amount) = invoice.amount {
                    NumericalBalanceView(text: NumberFormatter.localizedString(from: NSNumber(value: (Double(amount) / 1000.0)), number: .decimal), hide_balance: .constant(false))
                }
                
                Text("Bolt11 Invoice", comment: "Label for the bolt11 invoice string in confirmation screen")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text(verbatim: invoice.abbreviated)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(DamusColors.adaptableGrey)
                    .cornerRadius(10)
                    .frame(maxWidth: .infinity)
            }
            
            HStack(spacing: 15) {
                Button(action: {
                    sendState = .enterInvoice(scannerMessage: nil)
                }) {
                    Text("Back", comment: "Button to go back to invoice input")
                        .font(.headline)
                        .frame(minWidth: 140)
                        .padding()
                }
                .buttonStyle(NeutralButtonStyle())
                
                Button(action: {
                    sendState = .processing
                    
                    // Process payment
                    guard let payRequestEv = damus_state.nostrNetwork.nwcPay(url: nwc, post: damus_state.nostrNetwork.postbox, invoice: invoice.string, zap_request: nil) else {
                        sendState = .failed(error: .init(
                            user_visible_description: NSLocalizedString("The payment request could not be made to your wallet provider.", comment: "A human-readable error message"),
                            tip: NSLocalizedString("Check if your wallet looks configured correctly and try again. If the error persists, please contact support.", comment: "A human-readable tip for an error when a payment request cannot be made to a wallet."),
                            technical_info: "Cannot form Nostr Event to send to the NWC provider when calling `pay` from the \"send payment\" feature. Wallet provider relay: \"\(nwc.relay)\""
                        ))
                        return
                    }
                    Task {
                        do {
                            let result = try await model.waitForResponse(for: payRequestEv.id, timeout: SEND_PAYMENT_TIMEOUT)
                            guard case .pay_invoice(_) = result else {
                                sendState = .failed(error: .init(
                                    user_visible_description: NSLocalizedString("Received an incorrect or unexpected response from the wallet provider. This looks like an issue with your wallet provider.", comment: "A human-readable error message"),
                                    tip: NSLocalizedString("Try again. If the error persists, please contact your wallet provider and/or our support team.", comment: "A human-readable tip for an error when a payment request cannot be made to a wallet."),
                                    technical_info: "Expected a `pay_invoice` response for the request, but received a different type of response from the NWC wallet provider. Wallet provider relay: \"\(nwc.relay)\""
                                ))
                                return
                            }
                            sendState = .completed
                        }
                        catch {
                            if let error = error as? WalletModel.WaitError {
                                switch error {
                                case .timeout:
                                    sendState = .failed(error: .init(
                                        user_visible_description: NSLocalizedString("The payment request did not receive a response and the request timed-out.", comment: "A human-readable error message"),
                                        tip: NSLocalizedString("Check if the invoice is valid, your wallet is online, configured correctly, and try again. If the error persists, please contact support and/or your wallet provider.", comment: "A human-readable tip guiding the user on what to do when seeing a timeout error while sending a wallet payment."),
                                        technical_info: "Payment request timed-out. Wallet provider relay: \"\(nwc.relay)\""
                                    ))
                                }
                            }
                            else if let error = error as? WalletConnect.WalletResponseErr,
                                    let humanReadableError = error.humanReadableError  {
                                sendState = .failed(error: humanReadableError)
                            }
                            else {
                                sendState = .failed(error: .init(
                                    user_visible_description: NSLocalizedString("An unexpected error occurred.", comment: "A human-readable error message"),
                                    tip: NSLocalizedString("Please try again. If the error persists, please contact support.", comment: "A human-readable tip guiding the user on what to do when seeing an unexpected error while sending a wallet payment."),
                                    technical_info: "Unexpected error thrown while waiting for payment request response. Wallet provider relay: \"\(nwc.relay)\"; Error: \(error)"
                                ))
                            }
                        }
                    }
                }) {
                    Text("Confirm", comment: "Button to confirm payment")
                        .font(.headline)
                        .frame(minWidth: 140)
                        .padding()
                }
                .buttonStyle(GradientButtonStyle(padding: 0))
                .disabled(insufficientFunds)
                .opacity(insufficientFunds ? 0.5 : 1.0)
            }
            
            if insufficientFunds {
                Text("You do not have enough funds to pay for this invoice.", comment: "Label on invoice payment screen, indicating user has insufficient funds")
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
    }
    
    var processingView: some View {
        VStack(spacing: 30) {
            Text("Processing Payment", comment: "Title for payment processing screen")
                .font(.title2)
                .bold()
            
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Text("Please wait while your payment is being processed…", comment: "Message while payment is being processed")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding()
            
            Spacer()
        }
    }
    
    var completedView: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.green)
            
            Text("Payment Sent!", comment: "Title for successful payment screen")
                .font(.title2)
                .bold()
            
            Text("Your payment has been successfully sent.", comment: "Message for successful payment")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding()
            
            Button(action: {
                dismiss()
            }) {
                Text("Done", comment: "Button to dismiss successful payment screen")
                    .font(.headline)
                    .frame(minWidth: 200)
            }
            .buttonStyle(GradientButtonStyle())
            
            Spacer()
        }
    }
    
    func failedView(error: HumanReadableError) -> some View {
        ScrollView {
            VStack {
                ErrorView(damus_state: damus_state, error: error)
                
                Button(action: {
                    sendState = .enterInvoice(scannerMessage: nil)
                }) {
                    Text("Try Again", comment: "Button to retry payment")
                        .font(.headline)
                        .frame(minWidth: 200)
                        .padding()
                }
                .buttonStyle(GradientButtonStyle(padding: 0))
            }
        }
    }
    
    func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            processUserInput(result.string)
        case .failure(let error):
            sendState = .enterInvoice(scannerMessage: NSLocalizedString("Failed to scan QR code, please try again.", comment: "Error message for failed QR scan"))
        }
    }
    
    func processUserInput(_ text: String) {
        if let result = parseScanData(text) {
            switch result {
            case .invoice(let invoice):
                if invoice.amount == .any {
                    sendState = .enterInvoice(scannerMessage: NSLocalizedString("Sorry, we do not support paying invoices without amount yet. Please scan an invoice with an amount.", comment: "A user-readable message indicating that the lightning invoice they scanned or pasted is not supported and is missing an amount."))
                } else {
                    sendState = .confirmPayment(invoice: invoice)
                }
            case .lnurl(let lnurlString):
                sendState = .enterLnurlAmount(lnurl: lnurlString)
            }
        } else {
            sendState = .enterInvoice(scannerMessage: NSLocalizedString("This does not appear to be a valid Lightning invoice or LNURL.", comment: "A user-readable message indicating that the scanned or pasted content was not a valid lightning invoice or LNURL."))
        }
    }
    
    func parseScanData(_ text: String) -> ScanData? {
        let processedString = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if let invoice = Invoice.from(string: processedString) {
            return .invoice(invoice)
        }
        
        if let _ = processedString.range(of: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", options: .regularExpression) {
            guard let lnurl = lnaddress_to_lnurl(processedString) else { return nil }
            return .lnurl(lnurl)
        }
        
        if processedString.hasPrefix("lnurl") {
            return .lnurl(processedString)
        }
        
        return nil
    }
    
    enum ScanData {
        case invoice(Invoice)
        case lnurl(String)
    }
    
    // Helper function to get pasteboard content
    func getPasteboardContent() -> String? {
        return UIPasteboard.general.string
    }
}
