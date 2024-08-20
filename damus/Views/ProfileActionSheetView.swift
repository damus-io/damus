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
        return profile_txn?.unsafeUnownedValue
    }
    
    func get_profile() -> Profile? {
        return self.profile_data()?.profile
    }
    
    var followButton: some View {
        return ProfileActionSheetFollowButton(
            target: .pubkey(self.profile.pubkey),
            follows_you: self.profile.follows(pubkey: damus_state.pubkey),
            follow_state: damus_state.contacts.follow_state(profile.pubkey)
        )
    }
    
    var muteButton: some View {
        let target_pubkey = self.profile.pubkey
        return VStack(alignment: .center, spacing: 10) {
                MuteDurationMenu { duration in
                    notify(.mute(.user(target_pubkey, duration?.date_from_now)))
                } label: {
                    Image("mute")
                }
            .buttonStyle(NeutralButtonShape.circle.style)
            Text("Mute", comment: "Button label that allows the user to mute the user shown on-screen")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
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
            .buttonStyle(NeutralButtonShape.circle.style)
            Text("Message", comment: "Button label that allows the user to start a direct message conversation with the user shown on-screen")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
    
    var zapButton: some View {
        if let lnurl = self.profile_data()?.lnurl, lnurl != "" {
            return AnyView(ProfileActionSheetZapButton(damus_state: damus_state, profile: profile, lnurl: lnurl))
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
                self.followButton
                self.zapButton
                self.dmButton
                if damus_state.keypair.pubkey != profile.pubkey && damus_state.keypair.privkey != nil {
                    self.muteButton
                }
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
                        Text("View full profile", comment: "A button label that allows the user to see the full profile of the profile they are previewing")
                        Image(systemName: "arrow.up.right")
                        Spacer()
                    }
                    
                }
            )
            .buttonStyle(NeutralButtonShape.circle.style)
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

fileprivate struct ProfileActionSheetFollowButton: View {
    @Environment(\.colorScheme) var colorScheme
    
    let target: FollowTarget
    let follows_you: Bool
    @State var follow_state: FollowState
    
    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Button(
                action: {
                    follow_state = perform_follow_btn_action(follow_state, target: target)
                },
                label: {
                    switch follow_state {
                        case .unfollows:
                            Image("user-add-down")
                                .foregroundColor(Color.primary)
                                .profile_button_style(scheme: colorScheme)
                        default:
                            Image("user-added")
                                .foregroundColor(Color.green)
                                .profile_button_style(scheme: colorScheme)
                    }
                    
                }
            )
            .buttonStyle(NeutralButtonShape.circle.style)
            
            Text(verbatim: "\(follow_btn_txt(follow_state, follows_you: follows_you))")
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .onReceive(handle_notify(.followed)) { follow in
            guard case .pubkey(let pk) = follow,
                  pk == target.pubkey else { return }

            self.follow_state = .follows
        }
        .onReceive(handle_notify(.unfollowed)) { unfollow in
            guard case .pubkey(let pk) = unfollow,
                  pk == target.pubkey else { return }

            self.follow_state = .unfollows
        }
    }
}
    

fileprivate struct ProfileActionSheetZapButton: View {
    enum ZappingState: Equatable {
        case not_zapped
        case zapping
        case zap_success
        case zap_failure(error: ZappingError)
        
        func error_message() -> String? {
            switch self {
                case .zap_failure(let error):
                    return error.humanReadableMessage()
                default:
                    return nil
            }
        }
    }
    
    let damus_state: DamusState
    @StateObject var profile: ProfileModel
    let lnurl: String
    @State var zap_state: ZappingState = .not_zapped
    @State var show_error_alert: Bool = false
    
    @Environment(\.colorScheme) var colorScheme
    
    func receive_zap(zap_ev: ZappingEvent) {
        print("Received zap event")
        guard zap_ev.target == ZapTarget.profile(self.profile.pubkey) else {
            return
        }
        
        switch zap_ev.type {
            case .failed(let err):
                zap_state = .zap_failure(error: err)
                show_error_alert = true
                break
            case .got_zap_invoice(let inv):
                if damus_state.settings.show_wallet_selector {
                    present_sheet(.select_wallet(invoice: inv))
                } else {
                    let wallet = damus_state.settings.default_wallet.model
                    do {
                        try open_with_wallet(wallet: wallet, invoice: inv)
                    }
                    catch {
                        present_sheet(.select_wallet(invoice: inv))
                    }
                }
                break
            case .sent_from_nwc:
                zap_state = .zap_success
                break
        }
    }
    
    var button_label: String {
        switch zap_state {
            case .not_zapped:
                return NSLocalizedString("Zap", comment: "Button label that allows the user to zap (i.e. send a Bitcoin tip via the lightning network) the user shown on-screen")
            case .zapping:
                return NSLocalizedString("Zapping", comment: "Button label indicating that a zap action is in progress (i.e. the user is currently sending a Bitcoin tip via the lightning network to the user shown on-screen) ")
            case .zap_success:
                return NSLocalizedString("Zapped!", comment: "Button label indicating that a zap action was successful (i.e. the user is successfully sent a Bitcoin tip via the lightning network to the user shown on-screen) ")
            case .zap_failure(_):
                return NSLocalizedString("Zap failed", comment: "Button label indicating that a zap action was unsuccessful (i.e. the user was unable to send a Bitcoin tip via the lightning network to the user shown on-screen) ")
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Button(
                action: {
                    send_zap(damus_state: damus_state, target: .profile(self.profile.pubkey), lnurl: lnurl, is_custom: false, comment: nil, amount_sats: nil, zap_type: damus_state.settings.default_zap_type)
                    zap_state = .zapping
                },
                label: {
                    switch zap_state {
                        case .not_zapped:
                            Image("zap")
                                .foregroundColor(Color.primary)
                                .profile_button_style(scheme: colorScheme)
                        case .zapping:
                            ProgressView()
                                .foregroundColor(Color.primary)
                                .profile_button_style(scheme: colorScheme)
                        case .zap_success:
                            Image("checkmark")
                                .foregroundColor(Color.green)
                                .profile_button_style(scheme: colorScheme)
                        case .zap_failure:
                            Image("close")
                                .foregroundColor(Color.red)
                                .profile_button_style(scheme: colorScheme)
                    }
                    
                }
            )
            .disabled({
                switch zap_state {
                    case .not_zapped:
                        return false
                    default:
                        return true
                }
            }())
            .buttonStyle(NeutralButtonShape.circle.style)
            
            Text(button_label)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .onReceive(handle_notify(.zapping)) { zap_ev in
            receive_zap(zap_ev: zap_ev)
        }
        .simultaneousGesture(LongPressGesture().onEnded {_  in
            present_sheet(.zap(target: .profile(self.profile.pubkey), lnurl: lnurl))
        })
        .alert(isPresented: $show_error_alert) {
            Alert(
                title: Text("Zap failed", comment: "Title of an alert indicating that a zap action failed"),
                message: Text(zap_state.error_message() ?? ""),
                dismissButton: .default(Text("OK", comment: "Button label to dismiss an error dialog"))
            )
        }
        .onChange(of: zap_state) { new_zap_state in
            switch new_zap_state {
                case .zap_success, .zap_failure:
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation {
                            zap_state = .not_zapped
                        }
                    }
                    break
                default:
                    break
            }
        }
    }
}

struct InnerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

func show_profile_action_sheet_if_enabled(damus_state: DamusState, pubkey: Pubkey) {
    if damus_state.settings.show_profile_action_sheet_on_pfp_click {
        notify(.present_sheet(Sheets.profile_action(pubkey)))
    }
    else {
        damus_state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
    }
}

#Preview {
    ProfileActionSheetView(damus_state: test_damus_state, pubkey: test_pubkey)
}
