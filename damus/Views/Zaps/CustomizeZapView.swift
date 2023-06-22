//
//  CustomizeZapView.swift
//  damus
//
//  Created by William Casarin on 2023-02-25.
//

import SwiftUI
import Combine

struct ZapAmountItem: Identifiable, Hashable {
    let amount: Int
    let icon: String
    
    var id: String {
        return icon
    }
}

func get_default_zap_amount_item(_ def: Int) -> ZapAmountItem {
    return ZapAmountItem(amount: def, icon: "🤙")
}

func get_zap_amount_items(_ default_zap_amt: Int) -> [ZapAmountItem] {
    let def_item = get_default_zap_amount_item(default_zap_amt)
    var entries = [
        ZapAmountItem(amount: 69, icon: "😘"),
        ZapAmountItem(amount: 420, icon: "🌿"),
        ZapAmountItem(amount: 5000, icon: "💜"),
        ZapAmountItem(amount: 10_000, icon: "😍"),
        ZapAmountItem(amount: 20_000, icon: "🤩"),
        ZapAmountItem(amount: 50_000, icon: "🔥"),
        ZapAmountItem(amount: 100_000, icon: "🚀"),
        ZapAmountItem(amount: 1_000_000, icon: "🤯"),
    ]
    entries.append(def_item)
    
    entries.sort { $0.amount < $1.amount }
    return entries
}

func satsString(_ count: Int, locale: Locale = Locale.current) -> String {
    let format = localizedStringFormat(key: "sats", locale: locale)
    return String(format: format, locale: locale, count)
}

struct CustomizeZapView: View {
    let state: DamusState
    let target: ZapTarget
    let lnurl: String
    
    let zap_amounts: [ZapAmountItem]
    
    @StateObject var model: CustomizeZapModel = CustomizeZapModel()
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    func fillColor() -> Color {
        colorScheme == .light ? DamusColors.white : DamusColors.black
    }
    
    func fontColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }
    
    init(state: DamusState, target: ZapTarget, lnurl: String) {
        self.target = target
        self.zap_amounts = get_zap_amount_items(state.settings.default_zap_amount)
        self.lnurl = lnurl
        self.state = state
    }
    
    func amount_parts(_ n: Int) -> [ZapAmountItem] {
        var i: Int = -1
        let start = n * 3
        let end = start + 3
        
        return zap_amounts.filter { _ in
            i += 1
            return i >= start && i < end
        }
    }
    
    func AmountsPart(n: Int) -> some View {
        HStack(alignment: .center, spacing: 15) {
            ForEach(amount_parts(n)) { entry in
                ZapAmountButton(zapAmountItem: entry, action: {
                    model.custom_amount_sats = entry.amount
                    model.custom_amount = String(entry.amount)
                })
            }
        }
    }
    
    var AmountPicker: some View {
        VStack {
            AmountsPart(n: 0)
            
            AmountsPart(n: 1)
            
            AmountsPart(n: 2)
        }
        .padding(10)
    }
    
    func ZapAmountButton(zapAmountItem: ZapAmountItem, action: @escaping () -> ()) -> some View {
        Button(action: action) {
            let fmt = format_msats_abbrev(Int64(zapAmountItem.amount) * 1000)
            Text(verbatim: "\(zapAmountItem.icon)\n\(fmt)")
                .contentShape(Rectangle())
                .font(.headline)
                .frame(width: 70, height: 70)
                .foregroundColor(fontColor())
                .background(model.custom_amount_sats == zapAmountItem.amount ? fillColor() : DamusColors.adaptableGrey)
                .cornerRadius(15)
                .overlay(RoundedRectangle(cornerRadius: 15)
                    .stroke(DamusColors.purple.opacity(model.custom_amount_sats == zapAmountItem.amount ? 1.0 : 0.0), lineWidth: 2))
        }
    }
    
    var CustomZapTextField: some View {
        VStack(alignment: .center, spacing: 0) {
            TextField("", text: $model.custom_amount)
                .placeholder(when: model.custom_amount.isEmpty, alignment: .center) {
                Text(verbatim: 0.formatted())
            }
            .accentColor(.clear)
            .font(.system(size: 72, weight: .heavy))
            .minimumScaleFactor(0.01)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .onChange(of: model.custom_amount) { newValue in
                if let parsed = handle_string_amount(new_value: newValue) {
                    model.custom_amount = parsed.formatted()
                    model.custom_amount_sats = parsed
                } else {
                   model.custom_amount = ""
                   model.custom_amount_sats = nil
               }
            }
            Text(verbatim: satsString(model.custom_amount_sats ?? 0))
                .font(.system(size: 18, weight: .heavy))
        }
    }
    
    var ZapReply: some View {
        HStack {
            if #available(iOS 16.0, *) {
                TextField(NSLocalizedString("Send a message with your zap...", comment: "Placeholder text for a comment to send as part of a zap to the user."), text: $model.comment, axis: .vertical)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .lineLimit(5)
            } else {
                TextField(NSLocalizedString("Send a message with your zap...", comment: "Placeholder text for a comment to send as part of a zap to the user."), text: $model.comment)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
            }
        }
        .frame(minHeight: 30)
        .padding(10)
        .background(.secondary.opacity(0.2))
        .cornerRadius(10)
        .padding(.horizontal, 10)
    }
    
    var ZapButton: some View {
        VStack {
            if model.zapping {
                Text("Zapping...", comment: "Text to indicate that the app is in the process of sending a zap.")
            } else {
                Button(NSLocalizedString("Zap", comment: "Button to send a zap.")) {
                    let amount = model.custom_amount_sats
                    send_zap(damus_state: state, target: target, lnurl: lnurl, is_custom: true, comment: model.comment, amount_sats: amount, zap_type: model.zap_type)
                    model.zapping = true
                }
                .disabled(model.custom_amount_sats == 0 || model.custom_amount.isEmpty)
                .font(.system(size: 28, weight: .bold))
                .frame(width: 130, height: 50)
                .foregroundColor(.white)
                .background(LINEAR_GRADIENT)
                .opacity(model.custom_amount_sats == 0 || model.custom_amount.isEmpty ? 0.5 : 1.0)
                .clipShape(Capsule())
            }
            
            if let error = model.error {
                Text(error)
                    .foregroundColor(.red)
            }
        }
    }
    
    func receive_zap(notif: Notification) {
        let zap_ev = notif.object as! ZappingEvent
        guard zap_ev.is_custom else {
            return
        }
        guard zap_ev.target.id == target.id else {
            return
        }
        
        model.zapping = false
        
        switch zap_ev.type {
        case .failed(let err):
            switch err {
            case .fetching_invoice:
                model.error = NSLocalizedString("Error fetching lightning invoice", comment: "Message to display when there was an error fetching a lightning invoice while attempting to zap.")
            case .bad_lnurl:
                model.error = NSLocalizedString("Invalid lightning address", comment: "Message to display when there was an error attempting to zap due to an invalid lightning address.")
            case .canceled:
                model.error = NSLocalizedString("Zap attempt from connected wallet was canceled.", comment: "Message to display when a zap from the user's connected wallet was canceled.")
            case .send_failed:
                model.error = NSLocalizedString("Zap attempt from connected wallet failed.", comment: "Message to display when sending a zap from the user's connected wallet failed.")
            }
            break
        case .got_zap_invoice(let inv):
            if state.settings.show_wallet_selector {
                model.invoice = inv
                model.showing_wallet_selector = true
            } else {
                end_editing()
                let wallet = state.settings.default_wallet.model
                open_with_wallet(wallet: wallet, invoice: inv)
                model.showing_wallet_selector = false
                dismiss()
            }
        case .sent_from_nwc:
            dismiss()
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            ZapTypeButton()
                .padding(.top, 50)
            
            Spacer()

            CustomZapTextField
            
            AmountPicker
            
            ZapReply
            
            ZapButton
            
            Spacer()
        }
        .sheet(isPresented: $model.show_zap_types) {
            if #available(iOS 16.0, *) {
                ZapPicker
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            } else {
                ZapPicker
            }
        }
        .sheet(isPresented: $model.showing_wallet_selector) {
            SelectWalletView(default_wallet: state.settings.default_wallet, showingSelectWallet: $model.showing_wallet_selector, our_pubkey: state.pubkey, invoice: model.invoice)
        }
        .onAppear {
            model.set_defaults(settings: state.settings)
        }
        .onReceive(handle_notify(.zapping)) { notif in
            receive_zap(notif: notif)
        }
        .background(fillColor().edgesIgnoringSafeArea(.all))
        .onTapGesture {
            hideKeyboard()
        }
    }
    
    func ZapTypeButton() -> some View {
        Button(action: {
            model.show_zap_types = true
        }) {
            switch model.zap_type {
            case .pub:
                Image("globe")
                Text("Public", comment: "Button text to indicate that the zap type is a public zap.")
            case .anon:
                Image("question")
                Text("Anonymous", comment: "Button text to indicate that the zap type is a anonymous zap.")
            case .priv:
                Image("lock")
                Text("Private", comment: "Button text to indicate that the zap type is a private zap.")
            case .non_zap:
                Image("zap")
                Text("None", comment: "Button text to indicate that the zap type is a private zap.")
            }
        }
        .font(.headline)
        .foregroundColor(fontColor())
        .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
        .background(DamusColors.adaptableGrey)
        .cornerRadius(15)
    }

    var ZapPicker: some View {
        ZapTypePicker(zap_type: $model.zap_type, settings: state.settings, profiles: state.profiles, pubkey: target.pubkey)
    }
}

extension View {
    func hideKeyboard() {
        let resign = #selector(UIResponder.resignFirstResponder)
        UIApplication.shared.sendAction(resign, to: nil, from: nil, for: nil)
    }
}

struct CustomizeZapView_Previews: PreviewProvider {
    static var previews: some View {
        CustomizeZapView(state: test_damus_state(), target: ZapTarget.note(id: test_event.id, author: test_event.pubkey), lnurl: "")
            .frame(width: 400, height: 600)
    }
}
