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
        let zap_amt = get_default_zap_amount(pubkey: pubkey).map({ "\($0)" }) ?? "1000"
        _default_zap_amount = State(initialValue: zap_amt)
        self._settings = ObservedObject(initialValue: settings)
    }
    
    var body: some View {
        Form {
            Section("Wallet") {
                
                Toggle(NSLocalizedString("Show wallet selector", comment: "Toggle to show or hide selection of wallet."), isOn: $settings.show_wallet_selector).toggleStyle(.switch)
                Picker(NSLocalizedString("Select default wallet", comment: "Prompt selection of user's default wallet"),
                       selection: $settings.default_wallet) {
                    ForEach(Wallet.allCases, id: \.self) { wallet in
                        Text(wallet.model.displayName)
                            .tag(wallet.model.tag)
                    }
                }
            }
            
            Section("Zaps") {
                Toggle(NSLocalizedString("Zap Vibration", comment: "Setting to enable vibration on zap"), isOn: $settings.zap_vibration)
                    .toggleStyle(.switch)
            }
            
            Section("Default Zap Amount in sats") {
                TextField(String("1000"), text: $default_zap_amount)
                    .keyboardType(.numberPad)
                    .onReceive(Just(default_zap_amount)) { newValue in
                        if let parsed = handle_string_amount(new_value: newValue) {
                            self.default_zap_amount = String(parsed)
                            set_default_zap_amount(pubkey: self.pubkey, amount: parsed)
                        }
                    }
            }
        }
        .navigationTitle("Zaps")
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
