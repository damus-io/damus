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

func get_default_zap_amount_item(_ pubkey: String) -> ZapAmountItem {
    let def = get_default_zap_amount(pubkey: pubkey) ?? 1000
    return ZapAmountItem(amount: def, icon: "🤙")
}

func get_zap_amount_items(pubkey: String) -> [ZapAmountItem] {
    let def_item = get_default_zap_amount_item(pubkey)
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
    @State var selected_amount: ZapAmountItem
    @State var zap_type: ZapType
    @State var invoice: String
    @State var error: String?
    @State var showing_wallet_selector: Bool
    @State var zapping: Bool
    
    let zap_amounts: [ZapAmountItem]
    
    @Environment(\.dismiss) var dismiss
    
    init(state: DamusState, event: NostrEvent, lnurl: String) {
        self._comment = State(initialValue: "")
        self.event = event
        self.zap_amounts = get_zap_amount_items(pubkey: state.pubkey)
        self._error = State(initialValue: nil)
        self._invoice = State(initialValue: "")
        self._showing_wallet_selector = State(initialValue: false)
        self._custom_amount = State(initialValue: "")
        self._zap_type = State(initialValue: .pub)
        let selected = get_default_zap_amount_item(state.pubkey)
        self._selected_amount = State(initialValue: selected)
        self._custom_amount_sats = State(initialValue: nil)
        self._zapping = State(initialValue: false)
        self.lnurl = lnurl
        self.state = state
    }
    
    var zap_type_desc: String {
        switch zap_type {
        case .pub:
            return NSLocalizedString("Everyone on can see that you zapped", comment: "Description of public zap type where the zap is sent publicly and identifies the user who sent it.")
        case .anon:
            return NSLocalizedString("No one can see that you zapped", comment: "Description of anonymous zap type where the zap is sent anonymously and does not identify the user who sent it.")
        case .priv:
            let pk = event.pubkey
            let prof = state.profiles.lookup(id: pk)
            let name = Profile.displayName(profile: prof, pubkey: pk).username
            return String.localizedStringWithFormat(NSLocalizedString("private_zap_description", value: "Only '%@' can see that you zapped them", comment: "Description of private zap type where the zap is sent privately and does not identify the user to the public."), name)
        case .non_zap:
            return NSLocalizedString("No zaps are sent, only a lightning payment.", comment: "Description of non-zap type where sats are sent to the user's wallet as a regular Lightning payment, not as a zap.")
        }
    }
    
    var ZapTypePicker: some View {
        Picker(NSLocalizedString("Zap Type", comment: "Header text to indicate that the picker below it is to choose the type of zap to send."), selection: $zap_type) {
            Text("Public", comment: "Picker option to indicate that a zap should be sent publicly and identify the user as who sent it.").tag(ZapType.pub)
            Text("Private", comment: "Picker option to indicate that a zap should be sent privately and not identify the user to the public.").tag(ZapType.priv)
            Text("Anonymous", comment: "Picker option to indicate that a zap should be sent anonymously and not identify the user as who sent it.").tag(ZapType.anon)
            Text(verbatim: NSLocalizedString("none_zap_type", value: "None", comment: "Picker option to indicate that sats should be sent to the user's wallet as a regular Lightning payment, not as a zap.")).tag(ZapType.non_zap)
        }
        .pickerStyle(.menu)
    }
    
    var AmountPicker: some View {
        Picker(NSLocalizedString("Zap Amount", comment: "Title of picker that allows selection of predefined amounts to zap."), selection: $selected_amount) {
            ForEach(zap_amounts) { entry in
                let fmt = format_msats_abbrev(Int64(entry.amount) * 1000)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(entry.icon)")
                        .frame(width: 30)
                    Text("\(fmt)")
                        .frame(width: 50)
                }
                .tag(entry)
            }
        }
        .pickerStyle(.wheel)
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
            if should_show_wallet_selector(state.pubkey) {
                self.invoice = inv
                self.showing_wallet_selector = true
            } else {
                end_editing()
                open_with_wallet(wallet: get_default_wallet(state.pubkey).model, invoice: inv)
                self.showing_wallet_selector = false
                dismiss()
            }
        }
        
    
}
    
    var body: some View {
        MainContent
            .sheet(isPresented: $showing_wallet_selector) {
                SelectWalletView(showingSelectWallet: $showing_wallet_selector, our_pubkey: state.pubkey, invoice: invoice)
            }
            .onReceive(handle_notify(.zapping)) { notif in
                receive_zap(notif: notif)
            }
            .ignoresSafeArea()
    }
    
    var TheForm: some View {
        Form {
                
            Group {
                Section(content: {
                    AmountPicker
                        .frame(height: 120)
                }, header: {
                    Text("Zap Amount in sats", comment: "Header text to indicate that the picker below it is to choose a pre-defined amount of sats to zap.")
                })
                
                Section(content: {
                    TextField(String("100000"), text: $custom_amount)
                        .keyboardType(.numberPad)
                        .onReceive(Just(custom_amount)) { newValue in
                            
                            if let parsed = handle_string_amount(new_value: newValue) {
                                self.custom_amount = String(parsed)
                                self.custom_amount_sats = parsed
                            }
                        }
                }, header: {
                    Text("Custom Zap Amount", comment: "Header text to indicate that the text field below it is to enter a custom zap amount.")
                })
                
                Section(content: {
                    TextField(NSLocalizedString("Awesome post!", comment: "Placeholder text for a comment to send as part of a zap to the user."), text: $comment)
                }, header: {
                    Text("Comment", comment: "Header text to indicate that the text field below it is a comment that will be used to send as part of a zap to the user.")
                })
            }
            .dismissKeyboardOnTap()
                
            Section(content: {
                ZapTypePicker
            }, header: {
                Text("Zap Type", comment: "Header text to indicate that the picker below it is to choose the type of zap to send.")
            }, footer: {
                Text(zap_type_desc)
            })
            
            
            if zapping {
                Text("Zapping...", comment: "Text to indicate that the app is in the process of sending a zap.")
            } else {
                Button(NSLocalizedString("Zap", comment: "Button to send a zap.")) {
                    let amount = custom_amount_sats ?? selected_amount.amount
                    send_zap(damus_state: state, event: event, lnurl: lnurl, is_custom: true, comment: comment, amount_sats: amount, zap_type: zap_type)
                    self.zapping = true
                }
                .zIndex(16)
            }
            
            if let error {
                Text(error)
                    .foregroundColor(.red)
            }
        
        }
    }
    
    var MainContent: some View {
        TheForm
    }
}

struct CustomizeZapView_Previews: PreviewProvider {
    static var previews: some View {
        CustomizeZapView(state: test_damus_state(), event: test_event, lnurl: "")
            .frame(width: 400, height: 600)
    }
}
