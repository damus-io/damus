//
//  ProfileActionSheetView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-10-20.
//

import SwiftUI

struct ProfileActionSheetView: View {
    let damus_state: DamusState
    let pfp_size: CGFloat = 90.0

    @StateObject var profile: ProfileModel
    @StateObject var zap_button_model: ZapButtonModel = ZapButtonModel()
    @State private var sheetHeight: CGFloat = .zero
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
    
    init(damus_state: DamusState, pubkey: Pubkey) {
        self.damus_state = damus_state
        self._profile = StateObject(wrappedValue: ProfileModel(pubkey: pubkey, damus: damus_state))
    }

    func imageBorderColor() -> Color {
        colorScheme == .light ? DamusColors.white : DamusColors.black
    }
    
    func profile_data() -> ProfileRecord? {
        let profile_txn = damus_state.profiles.lookup_with_timestamp(profile.pubkey)
        return profile_txn.unsafeUnownedValue
    }
    
    func get_profile() -> Profile? {
        return self.profile_data()?.profile
    }
    
    var dmButton: some View {
        let dm_model = damus_state.dms.lookup_or_create(profile.pubkey)
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
            .buttonStyle(NeutralCircleButtonStyle())
            Text(NSLocalizedString("Message", comment: "Button label that allows the user to start a direct message conversation with the user shown on-screen"))
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    var zapButton: some View {
        if let lnurl = self.profile_data()?.lnurl, lnurl != "" {
            return AnyView(
                VStack(alignment: .center, spacing: 10) {
                    ProfileZapLinkView(damus_state: damus_state, pubkey: self.profile.pubkey, action: { dismiss() }) { reactions_enabled, lud16, lnurl in
                        Image(reactions_enabled ? "zap.fill" : "zap")
                            .foregroundColor(reactions_enabled ? .orange : Color.primary)
                            .profile_button_style(scheme: colorScheme)
                    }
                    .buttonStyle(NeutralCircleButtonStyle())
                    
                    Text(NSLocalizedString("Zap", comment: "Button label that allows the user to zap (i.e. send a Bitcoin tip via the lightning network) the user shown on-screen"))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            )
        }
        else {
            return AnyView(EmptyView())
        }
    }
    
    var profileName: some View {
        let display_name = Profile.displayName(profile: self.get_profile(), pubkey: self.profile.pubkey).displayName
        return HStack(alignment: .center, spacing: 10) {
            Text(display_name)
                .font(.title)
        }
    }
    
    var body: some View {
        VStack(alignment: .center) {
            ProfilePicView(pubkey: profile.pubkey, size: pfp_size, highlight: .custom(imageBorderColor(), 4.0), profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
            if let url = self.profile_data()?.profile?.website_url {
                WebsiteLink(url: url, style: .accent)
                    .padding(.top, -15)
            }
            
            profileName
            
            PubkeyView(pubkey: profile.pubkey)
            
            if let about = self.profile_data()?.profile?.about {
                AboutView(state: damus_state, about: about, max_about_length: 140, text_alignment: .center)
                    .padding(.top)
            }
            
            HStack(spacing: 20) {
                self.dmButton
                self.zapButton
            }
            .padding()
            
            Button(
                action: {
                    damus_state.nav.push(route: Route.ProfileByKey(pubkey: profile.pubkey))
                    dismiss()
                },
                label: {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("View full profile", comment: "A button label that allows the user to see the full profile of the profile they are previewing"))
                        Image(systemName: "arrow.up.right")
                        Spacer()
                    }
                    
                }
            )
            
            .buttonStyle(NeutralCircleButtonStyle())
        }
        .padding()
        .padding(.top, 20)
        .overlay {
            GeometryReader { geometry in
                Color.clear.preference(key: InnerHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(InnerHeightPreferenceKey.self) { newHeight in
            sheetHeight = newHeight
        }
        .presentationDetents([.height(sheetHeight)])
    }
}

struct InnerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    ProfileActionSheetView(damus_state: test_damus_state, pubkey: test_pubkey)
}
