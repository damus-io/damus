//
//  CustomizeZapView.swift
//  damus
//
//  Created by William Casarin on 2023-02-25.
//

import SwiftUI
import Combine

enum ZapType {
    case pub
    case anon
    case priv
    case non_zap
}

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
        ZapAmountItem(amount: 500, icon: "🙂"),
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
        self._zap_type = State(initialValue: .pub)
        let default_amount = get_default_zap_amount_item(state.settings.default_zap_amount)
        self._selected_amount = State(initialValue: selected)
        self._custom_amount = State(initialValue: String(default_amount))
        self._custom_amount_sats = State(initialValue: nil)
        self._zapping = State(initialValue: false)
        self.lnurl = lnurl
        self.state = state
    }
    
    func zap_type_desc(type: ZapType) -> String {
        switch type {
        case .pub:
            return NSLocalizedString("Everyone will see that you zapped", comment: "Description of public zap type where the zap is sent publicly and identifies the user who sent it.")
        case .anon:
            return NSLocalizedString("No one will see that you zapped", comment: "Description of anonymous zap type where the zap is sent anonymously and does not identify the user who sent it.")
        case .priv:
            let pk = event.pubkey
            let prof = state.profiles.lookup(id: pk)
            let name = Profile.displayName(profile: prof, pubkey: pk).username
            return String.localizedStringWithFormat(NSLocalizedString("private_zap_description", value: "Only '%@' will see that you zapped them", comment: "Description of private zap type where the zap is sent privately and does not identify the user to the public."), name)
        case .non_zap:
            return NSLocalizedString("No zaps will be sent, only a lightning payment.", comment: "Description of non-zap type where sats are sent to the user's wallet as a regular Lightning payment, not as a zap.")
        }
    }
    
    var ZapTypePicker: some View {
        VStack(spacing: 20) {
            Text("Zap type")
                .font(.system(size: 18, weight: .heavy))
            ZapTypeSelection(text: "Public", comment: "Picker option to indicate that a zap should be sent publicly and identify the user as who sent it.", img: "person.2.circle.fill", action: {zap_type = ZapType.pub}, type: ZapType.pub)
            ZapTypeSelection(text: "Private", comment: "Picker option to indicate that a zap should be sent privately and not identify the user to the public.", img: "lock.circle.fill", action: {zap_type = ZapType.priv}, type: ZapType.priv)
            ZapTypeSelection(text: "Anonymous", comment: "Picker option to indicate that a zap should be sent anonymously and not identify the user as who sent it.", img: "person.crop.circle.fill.badge.questionmark", action: {zap_type = ZapType.anon}, type: ZapType.anon)
            ZapTypeSelection(text: "None", comment: "Picker option to indicate that sats should be sent to the user's wallet as a regular Lightning payment, not as a zap.", img: "bolt.circle.fill", action: {zap_type = ZapType.non_zap}, type: ZapType.non_zap)
        }
        .padding(.horizontal)
    }
    
    func ZapTypeSelection(text: LocalizedStringKey, comment: StaticString, img: String, action: @escaping () -> (), type: ZapType) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: img)
                        .foregroundColor(.gray)
                        .font(.system(size: 24))
                    Text(text, comment: comment)
                        .font(.system(size: 20, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal)
                Text(zap_type_desc(type: type))
                    .padding(.horizontal)
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 50, maxHeight: 70)
        .foregroundColor(fontColor())
        .background(zap_type == type ? fillColor() : DamusColors.adaptableGrey)
        .cornerRadius(15)
        .overlay(RoundedRectangle(cornerRadius: 15)
            .stroke(DamusColors.purple.opacity(zap_type == type ? 1.0 : 0.0), lineWidth: 2))
    }
    
    func ZapTypeButton() -> some View {
        Button(action: {
            show_zap_types = true
        }) {
            switch zap_type {
            case .pub:
                Image(systemName: "person.2")
                Text("Public")
            case .anon:
                Image(systemName: "person.fill.questionmark")
                Text("Anonymous")
            case .priv:
                Image(systemName: "lock")
                Text("Private")
            case .non_zap:
                Image(systemName: "bolt")
                Text("None")
            }
        }
        .font(.headline)
        .foregroundColor(fontColor())
        .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
        .background(DamusColors.adaptableGrey)
        .cornerRadius(15)
    }
    
    var AmountPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 15) {
                ForEach(zap_amounts) { entry in
                    ZapAmountButton(zapAmountItem: entry, action: {custom_amount_sats = entry.amount; custom_amount = String(entry.amount)})
                }
            }
            .padding(10)
        }
    }
    
    func ZapAmountButton(zapAmountItem: ZapAmountItem, action: @escaping () -> ()) -> some View {
        Button(action: action) {
            let fmt = format_msats_abbrev(Int64(zapAmountItem.amount) * 1000)
            Text("\(zapAmountItem.icon)\n\(fmt)")
        }
        .font(.headline)
        .frame(width: 70, height: 70)
        .foregroundColor(fontColor())
        .background(custom_amount_sats == zapAmountItem.amount ? fillColor() : DamusColors.adaptableGrey)
        .cornerRadius(15)
        .overlay(RoundedRectangle(cornerRadius: 15)
            .stroke(DamusColors.purple.opacity(custom_amount_sats == zapAmountItem.amount ? 1.0 : 0.0), lineWidth: 2))
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
            Text("sats")
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
                Button(NSLocalizedString("Zap ⚡️", comment: "Button to send a zap.")) {
                    let amount = custom_amount_sats
                    send_zap(damus_state: state, event: event, lnurl: lnurl, is_custom: true, comment: comment, amount_sats: amount, zap_type: zap_type)
                    self.zapping = true
                }
                .disabled(custom_amount_sats == 0 || custom_amount.isEmpty)
                .font(.system(size: 28, weight: .bold))
                .frame(width: 120, height: 50)
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
                ZapTypePicker
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            } else {
                ZapTypePicker
            }
        }
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
