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

enum ZapFields{
    case amount
    case comment
}

struct CustomizeZapView: View {
    let state: DamusState
    let target: ZapTarget
    let lnurl: String
    
    let zap_amounts: [ZapAmountItem]
    
    @FocusState var focusedTextField : ZapFields?
    
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
        let start = n * 4
        let end = start + 4
        
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
                .focused($focusedTextField, equals: ZapFields.amount)
                .task {
                    self.focusedTextField = .amount
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
    
    var ZapReply: some View {
        HStack {
            TextField(NSLocalizedString("Send a message with your zap...", comment: "Placeholder text for a comment to send as part of a zap to the user."), text: $model.comment, axis: .vertical)
                .focused($focusedTextField, equals: ZapFields.comment)
                .task {
                            self.focusedTextField = .comment
                }
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .lineLimit(5)
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
                Button(action: {
                    let amount = model.custom_amount_sats
                    send_zap(damus_state: state, target: target, lnurl: lnurl, is_custom: true, comment: model.comment, amount_sats: amount, zap_type: model.zap_type)
                    model.zapping = true
                }) {
                    HStack {
                        Text("Zap User", comment: "Button to send a zap.")
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
            }
        }
    }
    
    func receive_zap(zap_ev: ZappingEvent) {
        guard zap_ev.is_custom, zap_ev.target.id == target.id else {
            return
        }
        
        model.zapping = false
        
        switch zap_ev.type {
        case .failed(let err):
            model.error = err.humanReadableMessage()
            break
        case .got_zap_invoice(let inv):
            if state.settings.show_wallet_selector {
                model.invoice = inv
                present_sheet(.select_wallet(invoice: inv))
            } else {
                end_editing()
                let wallet = state.settings.default_wallet.model
                do {
                    try open_with_wallet(wallet: wallet, invoice: inv)
                    dismiss()
                }
                catch {
                    present_sheet(.select_wallet(invoice: inv))
                }
            }
        case .sent_from_nwc:
            dismiss()
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            ScrollView {
                HStack(alignment: .center) {
                    UserView(damus_state: state, pubkey: target.pubkey)
                    
                    ZapTypeButton()
                }
                .padding([.horizontal, .top])

                CustomZapTextField
                
                AmountPicker
                
                ZapReply
                
                ZapButton
                
                Spacer()
            }
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
        .onAppear {
            model.set_defaults(settings: state.settings)
        }
        .onReceive(handle_notify(.zapping)) { zap_ev in
            receive_zap(zap_ev: zap_ev)
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

struct ZapSheetViewIfPossible: View {
    let damus_state: DamusState
    let target: ZapTarget
    let lnurl: String?
    var zap_sheet: ZapSheet? {
        guard let lnurl else { return nil }
        return ZapSheet(target: target, lnurl: lnurl)
    }

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if let zap_sheet {
            CustomizeZapView(state: damus_state, target: zap_sheet.target, lnurl: zap_sheet.lnurl)
        }
        else {
            zap_sheet_not_possible
        }
    }

    var zap_sheet_not_possible: some View {
        VStack(alignment: .center, spacing: 20) {
            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 70)
            Text("User not zappable", comment: "Headline indicating a user cannot be zapped")
                .font(.headline)
            Text("This user cannot be zapped because they have not configured zaps on their account yet. Time to orange-pill?", comment: "Comment explaining why a user cannot be zapped.")
                .multilineTextAlignment(.center)
                .opacity(0.6)
            self.dm_button
        }
        .padding()
    }

    var dm_button: some View {
        let dm_model = damus_state.dms.lookup_or_create(target.pubkey)
        return VStack(alignment: .center, spacing: 10) {
            Button(
                action: {
                    damus_state.nav.push(route: Route.DMChat(dms: dm_model))
                    dismiss()
                },
                label: {
                    Image("messages")
                        .profile_button_style(scheme: colorScheme)
                }
            )
            .buttonStyle(NeutralButtonShape.circle.style)
            Text("Orange-pill", comment: "Button label that allows the user to start a direct message conversation with the user shown on-screen, to orange-pill them (i.e. help them to setup zaps)")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

extension View {
    func hideKeyboard() {
        let resign = #selector(UIResponder.resignFirstResponder)
        this_app.sendAction(resign, to: nil, from: nil, for: nil)
    }
}



fileprivate func test_zap_sheet() -> ZapSheet {
    let zap_target = ZapTarget.note(id: test_note.id, author: test_note.pubkey)
    let lnurl = ""
    return ZapSheet(target: zap_target, lnurl: lnurl)
}

#Preview {
    CustomizeZapView(state: test_damus_state, target: test_zap_sheet().target, lnurl: test_zap_sheet().lnurl)
        .frame(width: 400, height: 600)
}

#Preview {
    ZapSheetViewIfPossible(damus_state: test_damus_state, target: test_zap_sheet().target, lnurl: test_zap_sheet().lnurl)
        .frame(width: 400, height: 600)
}

#Preview {
    ZapSheetViewIfPossible(damus_state: test_damus_state, target: test_zap_sheet().target, lnurl: nil)
        .frame(width: 400, height: 600)
}
