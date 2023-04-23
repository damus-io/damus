//
//  ZapTypePicker.swift
//  damus
//
//  Created by William Casarin on 2023-04-23.
//

import SwiftUI

enum ZapType {
    case pub
    case anon
    case priv
    case non_zap
}

struct ZapTypePicker: View {
    @Binding var zap_type: ZapType
    let profiles: Profiles
    let pubkey: String
    
    @Environment(\.colorScheme) var colorScheme
    
    func fillColor() -> Color {
        colorScheme == .light ? DamusColors.white : DamusColors.black
    }
    
    func fontColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }
    
    var body: some View {
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
                Text(zap_type_desc(type: type, profiles: profiles, pubkey: pubkey))
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
}

struct ZapTypePicker_Previews: PreviewProvider {
    @State static var zap_type: ZapType = .pub
    static var previews: some View {
        let ds = test_damus_state()
        ZapTypePicker(zap_type: $zap_type, profiles: ds.profiles, pubkey: "bob")
    }
}

func zap_type_desc(type: ZapType, profiles: Profiles, pubkey: String) -> String {
    switch type {
    case .pub:
        return NSLocalizedString("Everyone will see that you zapped", comment: "Description of public zap type where the zap is sent publicly and identifies the user who sent it.")
    case .anon:
        return NSLocalizedString("No one will see that you zapped", comment: "Description of anonymous zap type where the zap is sent anonymously and does not identify the user who sent it.")
    case .priv:
        let prof = profiles.lookup(id: pubkey)
        let name = Profile.displayName(profile: prof, pubkey: pubkey).username
        return String.localizedStringWithFormat(NSLocalizedString("private_zap_description", value: "Only '%@' will see that you zapped them", comment: "Description of private zap type where the zap is sent privately and does not identify the user to the public."), name)
    case .non_zap:
        return NSLocalizedString("No zaps will be sent, only a lightning payment.", comment: "Description of non-zap type where sats are sent to the user's wallet as a regular Lightning payment, not as a zap.")
    }
}

