//
//  WalletSettingsView.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI
import Combine

struct ZapSettingsView: View {
    let pubkey: String
    @ObservedObject var settings: UserSettingsStore
    
    @State var default_zap_amount: String
    @Environment(\.dismiss) var dismiss

    init(pubkey: String, settings: UserSettingsStore) {
        self.pubkey = pubkey
        let zap_amt = get_default_zap_amount(pubkey: pubkey).formatted()
        _default_zap_amount = State(initialValue: zap_amt)
        self._settings = ObservedObject(initialValue: settings)
    }
    
    var body: some View {
        Form {
            Section(NSLocalizedString("Wallet", comment: "Title for section in zap settings that controls the Lightning wallet selection.")) {
                
                Toggle(NSLocalizedString("Show wallet selector", comment: "Toggle to show or hide selection of wallet."), isOn: $settings.show_wallet_selector).toggleStyle(.switch)
                Picker(NSLocalizedString("Select default wallet", comment: "Prompt selection of user's default wallet"),
                       selection: $settings.default_wallet) {
                    ForEach(Wallet.allCases, id: \.self) { wallet in
                        Text(wallet.model.displayName)
                            .tag(wallet.model.tag)
                    }
                }
            }
            
            Section(NSLocalizedString("Zaps", comment: "Title for section in zap settings that controls general zap preferences.")) {
                Toggle(NSLocalizedString("Zap Vibration", comment: "Setting to enable vibration on zap"), isOn: $settings.zap_vibration)
                    .toggleStyle(.switch)
            }
            
            Section(NSLocalizedString("Default Zap Amount in sats", comment: "Title for section in zap settings that controls the default zap amount in sats.")) {
                TextField(fallback_zap_amount.formatted(), text: $default_zap_amount)
                    .keyboardType(.numberPad)
                    .onReceive(Just(default_zap_amount)) { newValue in
                        if let parsed = handle_string_amount(new_value: newValue) {
                            self.default_zap_amount = parsed.formatted()
                            set_default_zap_amount(pubkey: self.pubkey, amount: parsed)
                        } else {
                            self.default_zap_amount = ""
                            set_default_zap_amount(pubkey: self.pubkey, amount: 0)
                        }
                    }
            }
        }
        .navigationTitle(NSLocalizedString("Zaps", comment: "Navigation title for zap settings."))
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
}

struct WalletSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ZapSettingsView(pubkey: "pubkey", settings: UserSettingsStore())
    }
}
