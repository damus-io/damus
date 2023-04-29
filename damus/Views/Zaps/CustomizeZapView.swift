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
    let event: NostrEvent
    let lnurl: String
    @State var comment: String
    @State var custom_amount: String
    @State var custom_amount_sats: Int?
    @State var zap_type: ZapType
    @State var invoice: String
    @State var error: String?
    @State var showing_wallet_selector: Bool
    @State var zapping: Bool
    @State var show_zap_types: Bool = false
    
    let zap_amounts: [ZapAmountItem]
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    func fillColor() -> Color {
        colorScheme == .light ? DamusColors.white : DamusColors.black
    }
    
    func fontColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }
    
    init(state: DamusState, event: NostrEvent, lnurl: String) {
        self._comment = State(initialValue: "")
        self.event = event
        self.zap_amounts = get_zap_amount_items(state.settings.default_zap_amount)
        self._error = State(initialValue: nil)
        self._invoice = State(initialValue: "")
        self._showing_wallet_selector = State(initialValue: false)
        self._zap_type = State(initialValue: state.settings.default_zap_type)
        self._custom_amount = State(initialValue: String(state.settings.default_zap_amount))
        self._custom_amount_sats = State(initialValue: nil)
        self._zapping = State(initialValue: false)
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
                ZapAmountButton(zapAmountItem: entry, action: {custom_amount_sats = entry.amount; custom_amount = String(entry.amount)})
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
                .background(custom_amount_sats == zapAmountItem.amount ? fillColor() : DamusColors.adaptableGrey)
                .cornerRadius(15)
                .overlay(RoundedRectangle(cornerRadius: 15)
                    .stroke(DamusColors.purple.opacity(custom_amount_sats == zapAmountItem.amount ? 1.0 : 0.0), lineWidth: 2))
        }
    }
    
    var CustomZapTextField: some View {
        VStack(alignment: .center, spacing: 0) {
            TextField("", text: $custom_amount)
            .placeholder(when: custom_amount.isEmpty, alignment: .center) {
                Text(String("0"))
            }
            .accentColor(.clear)
            .font(.system(size: 72, weight: .heavy))
            .minimumScaleFactor(0.01)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .onReceive(Just(custom_amount)) { newValue in
                if let parsed = handle_string_amount(new_value: newValue) {
                    self.custom_amount = parsed.formatted()
                    self.custom_amount_sats = parsed
                } else {
                   self.custom_amount = ""
                   self.custom_amount_sats = nil
               }
            }
            Text(verbatim: satsString(custom_amount_sats ?? 0))
                .font(.system(size: 18, weight: .heavy))
        }
    }
    
    var ZapReply: some View {
        HStack {
            if #available(iOS 16.0, *) {
                TextField(NSLocalizedString("Send a reply with your zap...", comment: "Placeholder text for a comment to send as part of a zap to the user."), text: $comment, axis: .vertical)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .lineLimit(5)
            } else {
                TextField(NSLocalizedString("Send a reply with your zap...", comment: "Placeholder text for a comment to send as part of a zap to the user."), text: $comment)
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
            if zapping {
                Text("Zapping...", comment: "Text to indicate that the app is in the process of sending a zap.")
            } else {
                Button(NSLocalizedString("Zap", comment: "Button to send a zap.")) {
                    let amount = custom_amount_sats
                    send_zap(damus_state: state, event: event, lnurl: lnurl, is_custom: true, comment: comment, amount_sats: amount, zap_type: zap_type)
                    self.zapping = true
                }
                .disabled(custom_amount_sats == 0 || custom_amount.isEmpty)
                .font(.system(size: 28, weight: .bold))
                .frame(width: 130, height: 50)
                .foregroundColor(.white)
                .background(LINEAR_GRADIENT)
                .opacity(custom_amount_sats == 0 || custom_amount.isEmpty ? 0.5 : 1.0)
                .clipShape(Capsule())
            }
            
            if let error {
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
        guard zap_ev.event.id == event.id else {
            return
        }
        
        self.zapping = false
        
        switch zap_ev.type {
        case .failed(let err):
            switch err {
            case .fetching_invoice:
                self.error = NSLocalizedString("Error fetching lightning invoice", comment: "Message to display when there was an error fetching a lightning invoice while attempting to zap.")
            case .bad_lnurl:
                self.error = NSLocalizedString("Invalid lightning address", comment: "Message to display when there was an error attempting to zap due to an invalid lightning address.")
            }
            break
        case .got_zap_invoice(let inv):
            if state.settings.show_wallet_selector {
                self.invoice = inv
                self.showing_wallet_selector = true
            } else {
                end_editing()
                let wallet = state.settings.default_wallet.model
                open_with_wallet(wallet: wallet, invoice: inv)
                self.showing_wallet_selector = false
                dismiss()
            }
        }
}
    
    var body: some View {
        MainContent
            .sheet(isPresented: $showing_wallet_selector) {
                SelectWalletView(default_wallet: state.settings.default_wallet, showingSelectWallet: $showing_wallet_selector, our_pubkey: state.pubkey, invoice: invoice)
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
            show_zap_types = true
        }) {
            switch zap_type {
            case .pub:
                Image(systemName: "person.2")
                Text("Public", comment: "Button text to indicate that the zap type is a public zap.")
            case .anon:
                Image(systemName: "person.fill.questionmark")
                Text("Anonymous", comment: "Button text to indicate that the zap type is a anonymous zap.")
            case .priv:
                Image(systemName: "lock")
                Text("Private", comment: "Button text to indicate that the zap type is a private zap.")
            case .non_zap:
                Image(systemName: "bolt")
                Text("None", comment: "Button text to indicate that the zap type is a private zap.")
            }
        }
        .font(.headline)
        .foregroundColor(fontColor())
        .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
        .background(DamusColors.adaptableGrey)
        .cornerRadius(15)
    }

    var CustomZap: some View {
        VStack(alignment: .center, spacing: 20) {
            
            ZapTypeButton()
                .padding(.top, 50)
            
            Spacer()

            CustomZapTextField
            
            AmountPicker
            
            ZapReply
            
            ZapButton
            
            Spacer()
            
            Spacer()
        }
        .sheet(isPresented: $show_zap_types) {
            if #available(iOS 16.0, *) {
                ZapPicker
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            } else {
                ZapPicker
            }
        }
    }
    
    var ZapPicker: some View {
        ZapTypePicker(zap_type: $zap_type, settings: state.settings, profiles: state.profiles, pubkey: event.pubkey)
    }
    
    var MainContent: some View {
        CustomZap
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
        CustomizeZapView(state: test_damus_state(), event: test_event, lnurl: "")
            .frame(width: 400, height: 600)
    }
}
