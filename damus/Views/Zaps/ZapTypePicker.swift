//
//  ZapTypePicker.swift
//  damus
//
//  Created by William Casarin on 2023-04-23.
//

import SwiftUI

struct ZapTypePicker: View {
    @Binding var zap_type: ZapType
    @ObservedObject var settings: UserSettingsStore
    let profiles: Profiles
    let pubkey: Pubkey
    
    @Environment(\.colorScheme) var colorScheme
    
    func fillColor() -> Color {
        colorScheme == .light ? DamusColors.white : DamusColors.black
    }
    
    func fontColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }
    
    var is_default: Bool {
        zap_type == settings.default_zap_type
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Zap type", comment: "Text to indicate that the buttons below it is for choosing the type of zap to send.")
                    .font(.system(size: 25, weight: .heavy))
                Spacer()
                if !is_default {
                    Button(action: {
                        settings.default_zap_type = zap_type
                    }) {
                        Label(NSLocalizedString("Make Default", comment: "Button label to indicate that tapping it will make the selected zap type be the default for future zaps."), image: "checkmark.circle.fill")
                    }
                }
            }
            ZapTypeSelection(text: NSLocalizedString("Public", comment: "Picker option to indicate that a zap should be sent publicly and identify the user as who sent it."), img: "globe", action: {zap_type = ZapType.pub}, type: ZapType.pub)
            ZapTypeSelection(text: NSLocalizedString("Private", comment: "Picker option to indicate that a zap should be sent privately and not identify the user to the public."), img: "lock", action: {zap_type = ZapType.priv}, type: ZapType.priv)
            ZapTypeSelection(text: NSLocalizedString("Anonymous", comment: "Picker option to indicate that a zap should be sent anonymously and not identify the user as who sent it."), img: "question", action: {zap_type = ZapType.anon}, type: ZapType.anon)
            ZapTypeSelection(text: NSLocalizedString("None", comment: "Picker option to indicate that sats should be sent to the user's wallet as a regular Lightning payment, not as a zap."), img: "zap", action: {zap_type = ZapType.non_zap}, type: ZapType.non_zap)
        }
        .padding(.horizontal)
    }
    
    func ZapTypeSelection(text: String, img: String, action: @escaping () -> (), type: ZapType) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundColor(.gray)
                    
                    Text(text)
                        .font(.system(size: 20, weight: .semibold))
                    
                    Spacer()
                }
                .padding(.horizontal)

                let zapTypeDescription = zap_type_desc(type: type, profiles: profiles, pubkey: pubkey)
                Text(zapTypeDescription)
                    .padding(.horizontal)
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 70)
        .foregroundColor(fontColor())
        .background(zap_type == type ? fillColor() : DamusColors.adaptableGrey)
        .cornerRadius(15)
        .overlay(RoundedRectangle(cornerRadius: 15)
            .stroke(DamusColors.purple.opacity(zap_type == type ? 1.0 : 0.0), lineWidth: 2))
    }
}

struct ZapTypePicker_Previews: PreviewProvider {
    @State static var zap_type: ZapType = .pub
    static var previews: some View {
        let ds = test_damus_state
        ZapTypePicker(zap_type: $zap_type, settings: ds.settings, profiles: ds.profiles, pubkey: test_pubkey)
    }
}

func zap_type_desc(type: ZapType, profiles: Profiles, pubkey: Pubkey) -> String {
    switch type {
    case .pub:
        return NSLocalizedString("Everyone will see that you zapped", comment: "Description of public zap type where the zap is sent publicly and identifies the user who sent it.")
    case .anon:
        return NSLocalizedString("No one will see that you zapped", comment: "Description of anonymous zap type where the zap is sent anonymously and does not identify the user who sent it.")
    case .priv:
        let prof_txn = profiles.lookup(id: pubkey)
        let prof = prof_txn.unsafeUnownedValue
        let name = Profile.displayName(profile: prof, pubkey: pubkey).username.truncate(maxLength: 50)
        return String.localizedStringWithFormat(NSLocalizedString("private_zap_description", value: "Only '%@' will see that you zapped them", comment: "Description of private zap type where the zap is sent privately and does not identify the user to the public."), name)
    case .non_zap:
        return NSLocalizedString("No zaps will be sent, only a lightning payment.", comment: "Description of non-zap type where sats are sent to the user's wallet as a regular Lightning payment, not as a zap.")
    }
}

