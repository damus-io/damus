//
//  ProfileView.swift
//  damus
//
//  Created by William Casarin on 2022-04-23.
//

import SwiftUI

func follow_btn_txt(_ fs: FollowState, follows_you: Bool) -> String {
    switch fs {
    case .follows:
        return NSLocalizedString("Unfollow", comment: "Button to unfollow a user.")
    case .following:
        return NSLocalizedString("Following...", comment: "Label to indicate that the user is in the process of following another user.")
    case .unfollowing:
        return NSLocalizedString("Unfollowing...", comment: "Label to indicate that the user is in the process of unfollowing another user.")
    case .unfollows:
        if follows_you {
            return NSLocalizedString("Follow Back", comment: "Button to follow a user back.")
        } else {
            return NSLocalizedString("Follow", comment: "Button to follow a user.")
        }
    }
}

func followedByString<Y>(txn: NdbTxn<Y>, _ friend_intersection: [Pubkey], ndb: Ndb, locale: Locale = Locale.current) -> String {
    let bundle = bundleForLocale(locale: locale)
    let names: [String] = friend_intersection.prefix(3).map { pk in
        let profile = ndb.lookup_profile_with_txn(pk, txn: txn)?.profile
        return Profile.displayName(profile: profile, pubkey: pk).username.truncate(maxLength: 20)
    }

    switch friend_intersection.count {
    case 0:
        return ""
    case 1:
        let format = NSLocalizedString("Followed by %@", bundle: bundle, comment: "Text to indicate that the user is followed by one of our follows.")
        return String(format: format, locale: locale, names[0])
    case 2:
        let format = NSLocalizedString("Followed by %@ & %@", bundle: bundle, comment: "Text to indicate that the user is followed by two of our follows.")
        return String(format: format, locale: locale, names[0], names[1])
    case 3:
        let format = NSLocalizedString("Followed by %@, %@ & %@", bundle: bundle, comment: "Text to indicate that the user is followed by three of our follows.")
        return String(format: format, locale: locale, names[0], names[1], names[2])
    default:
        let format = localizedStringFormat(key: "followed_by_three_and_others", locale: locale)
        return String(format: format, locale: locale, friend_intersection.count - 3, names[0], names[1], names[2])
    }
}

struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?

    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView {
        UIVisualEffectView()
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) {
        uiView.effect = effect
    }
}

struct ProfileView: View {
    let damus_state: DamusState
    let pfp_size: CGFloat = 90.0
    let bannerHeight: CGFloat = 150.0

    @State var is_zoomed: Bool = false
    @State var show_share_sheet: Bool = false
    @State var show_qr_code: Bool = false
    @State var action_sheet_presented: Bool = false
    @State var filter_state : FilterState = .posts
    @State var yOffset: CGFloat = 0

    @StateObject var profile: ProfileModel
    @StateObject var followers: FollowersModel
    @StateObject var zap_button_model: ZapButtonModel = ZapButtonModel()

    init(damus_state: DamusState, profile: ProfileModel, followers: FollowersModel) {
        self.damus_state = damus_state
        self._profile = StateObject(wrappedValue: profile)
        self._followers = StateObject(wrappedValue: followers)
    }

    init(damus_state: DamusState, pubkey: Pubkey) {
        self.damus_state = damus_state
        self._profile = StateObject(wrappedValue: ProfileModel(pubkey: pubkey, damus: damus_state))
        self._followers = StateObject(wrappedValue: FollowersModel(damus_state: damus_state, target: pubkey))
    }

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode

    func imageBorderColor() -> Color {
        colorScheme == .light ? DamusColors.white : DamusColors.black
    }

    func bannerBlurViewOpacity() -> Double  {
        let progress = -(yOffset + navbarHeight) / 100
        return Double(-yOffset > navbarHeight ? progress : 0)
    }
    
    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)
        return ContentFilters(filters: filters).filter
    }

    var bannerSection: some View {
        GeometryReader { proxy -> AnyView in

            let minY = proxy.frame(in: .global).minY

            DispatchQueue.main.async {
                self.yOffset = minY
            }

            return AnyView(
                VStack(spacing: 0) {
                    ZStack {
                        BannerImageView(pubkey: profile.pubkey, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: minY > 0 ? bannerHeight + minY : bannerHeight)
                            .clipped()

                        VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial)).opacity(bannerBlurViewOpacity())
                    }

                    Divider().opacity(bannerBlurViewOpacity())
                }
                .frame(height: minY > 0 ? bannerHeight + minY : nil)
                .offset(y: minY > 0 ? -minY : -minY < navbarHeight ? 0 : -minY - navbarHeight)
            )

        }
        .frame(height: bannerHeight)
        .allowsHitTesting(false)
    }

    var navbarHeight: CGFloat {
        return 100.0 - (Theme.safeAreaInsets?.top ?? 0)
    }

    func navImage(img: String) -> some View {
        Image(img)
            .frame(width: 33, height: 33)
            .background(Color.black.opacity(0.6))
            .clipShape(Circle())
    }

    var navBackButton: some View {
        Button {
            presentationMode.wrappedValue.dismiss()
        } label: {
            navImage(img: "chevron-left")
        }
    }

    var navActionSheetButton: some View {
        Button(action: {
            action_sheet_presented = true
        }) {
            navImage(img: "share3")
        }
        .confirmationDialog(NSLocalizedString("Actions", comment: "Title for confirmation dialog to either share, report, or mute a profile."), isPresented: $action_sheet_presented) {
            Button(NSLocalizedString("Share", comment: "Button to share the link to a profile.")) {
                show_share_sheet = true
            }

            Button(NSLocalizedString("QR Code", comment: "Button to view profile's qr code.")) {
                show_qr_code = true
            }

            // Only allow reporting if logged in with private key and the currently viewed profile is not the logged in profile.
            if profile.pubkey != damus_state.pubkey && damus_state.is_privkey_user {
                Button(NSLocalizedString("Report", comment: "Button to report a profile."), role: .destructive) {
                    notify(.report(.user(profile.pubkey)))
                }

                if damus_state.contacts.is_muted(profile.pubkey) {
                    Button(NSLocalizedString("Unmute", comment: "Button to unmute a profile.")) {
                        guard
                            let keypair = damus_state.keypair.to_full(),
                            let mutelist = damus_state.contacts.mutelist
                        else {
                            return
                        }

                        guard let new_ev = remove_from_mutelist(keypair: keypair, prev: mutelist, to_remove: .pubkey(profile.pubkey)) else {
                            return
                        }

                        damus_state.contacts.set_mutelist(new_ev)
                        damus_state.postbox.send(new_ev)
                    }
                } else {
                    Button(NSLocalizedString("Mute", comment: "Button to mute a profile."), role: .destructive) {
                        notify(.mute(profile.pubkey))
                    }
                }
            }
        }
    }

    var customNavbar: some View {
        HStack {
            navBackButton
            Spacer()
            navActionSheetButton
        }
        .padding(.top, 5)
        .accentColor(DamusColors.white)
    }

    func lnButton(unownedProfile: Profile?, record: ProfileRecord?) -> some View {
        return ProfileZapLinkView(unownedProfileRecord: record, profileModel: self.profile) { reactions_enabled, lud16, lnurl in
            Image(reactions_enabled ? "zap.fill" : "zap")
                .foregroundColor(reactions_enabled ? .orange : Color.primary)
                .profile_button_style(scheme: colorScheme)
                .cornerRadius(24)
        }
    }
    
    var dmButton: some View {
        let dm_model = damus_state.dms.lookup_or_create(profile.pubkey)
        return NavigationLink(value: Route.DMChat(dms: dm_model)) {
            Image("messages")
                .profile_button_style(scheme: colorScheme)
        }
    }
    
    private var followsYouBadge: some View {
        Text("Follows you", comment: "Text to indicate that a user is following your profile.")
            .padding([.leading, .trailing], 6.0)
            .padding([.top, .bottom], 2.0)
            .foregroundColor(.gray)
            .background {
                RoundedRectangle(cornerRadius: 5.0)
                    .foregroundColor(DamusColors.adaptableGrey)
            }
            .font(.footnote)
    }

    func actionSection(record: ProfileRecord?, pubkey: Pubkey) -> some View {
        return Group {
            if let record,
               let profile = record.profile,
               let lnurl = record.lnurl,
               lnurl != ""
            {
                lnButton(unownedProfile: profile, record: record)
            }

            dmButton

            if profile.pubkey != damus_state.pubkey {
                FollowButtonView(
                    target: profile.get_follow_target(),
                    follows_you: profile.follows(pubkey: damus_state.pubkey),
                    follow_state: damus_state.contacts.follow_state(profile.pubkey)
                )
            } else if damus_state.keypair.privkey != nil {
                NavigationLink(value: Route.EditMetadata) {
                    ProfileEditButton(damus_state: damus_state)
                }
            }

        }
    }

    func pfpOffset() -> CGFloat {
        let progress = -yOffset / navbarHeight
        let offset = (pfp_size / 4.0) * (progress < 1.0 ? progress : 1)
        return offset > 0 ? offset : 0
    }

    func pfpScale() -> CGFloat {
        let progress = -yOffset / navbarHeight
        let scale = 1.0 - (0.5 * (progress < 1.0 ? progress : 1))
        return scale < 1 ? scale : 1
    }

    func nameSection(profile_data: ProfileRecord?) -> some View {
        return Group {
            let follows_you = profile.pubkey != damus_state.pubkey && profile.follows(pubkey: damus_state.pubkey)

            HStack(alignment: .center) {
                ProfilePicView(pubkey: profile.pubkey, size: pfp_size, highlight: .custom(imageBorderColor(), 4.0), profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                    .padding(.top, -(pfp_size / 2.0))
                    .offset(y: pfpOffset())
                    .scaleEffect(pfpScale())
                    .onTapGesture {
                        is_zoomed.toggle()
                    }
                    .fullScreenCover(isPresented: $is_zoomed) {
                        ProfilePicImageView(pubkey: profile.pubkey, profiles: damus_state.profiles, settings: damus_state.settings)
                    }

                Spacer()

                if follows_you {
                    followsYouBadge
                }

                actionSection(record: profile_data, pubkey: profile.pubkey)
            }

            ProfileNameView(pubkey: profile.pubkey, damus: damus_state)
        }
    }

    var followersCount: some View {
        HStack {
            if let followerCount = followers.count {
                let nounString = pluralizedString(key: "followers_count", count: followerCount)
                let nounText = Text(verbatim: nounString).font(.subheadline).foregroundColor(.gray)
                Text("\(Text(verbatim: followerCount.formatted()).font(.subheadline.weight(.medium))) \(nounText)", comment: "Sentence composed of 2 variables to describe how many people are following a user. In source English, the first variable is the number of followers, and the second variable is 'Follower' or 'Followers'.")
            } else {
                Image("download")
                    .resizable()
                    .frame(width: 20, height: 20)
                Text("Followers", comment: "Label describing followers of a user.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }

    var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            let profile_txn = damus_state.profiles.lookup_with_timestamp(profile.pubkey)
            let profile_data = profile_txn.unsafeUnownedValue

            nameSection(profile_data: profile_data)

            if let about = profile_data?.profile?.about {
                AboutView(state: damus_state, about: about)
            }

            if let url = profile_data?.profile?.website_url {
                WebsiteLink(url: url)
            }

            HStack {
                if let contact = profile.contacts {
                    let contacts = Array(contact.referenced_pubkeys)
                    let hashtags = Array(contact.referenced_hashtags)
                    let following_model = FollowingModel(damus_state: damus_state, contacts: contacts, hashtags: hashtags)
                    NavigationLink(value: Route.Following(following: following_model)) {
                        HStack {
                            let noun_text = Text(verbatim: "\(pluralizedString(key: "following_count", count: profile.following))").font(.subheadline).foregroundColor(.gray)
                            Text("\(Text(verbatim: profile.following.formatted()).font(.subheadline.weight(.medium))) \(noun_text)", comment: "Sentence composed of 2 variables to describe how many profiles a user is following. In source English, the first variable is the number of profiles being followed, and the second variable is 'Following'.")
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if followers.contacts != nil {
                    NavigationLink(value: Route.Followers(followers: followers)) {
                        followersCount
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    followersCount
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            followers.contacts = []
                            followers.subscribe()
                        }
                }

                if let relays = profile.relays {
                    // Only open relay config view if the user is logged in with private key and they are looking at their own profile.
                    let noun_string = pluralizedString(key: "relays_count", count: relays.keys.count)
                    let noun_text = Text(noun_string).font(.subheadline).foregroundColor(.gray)
                    let relay_text = Text("\(Text(verbatim: relays.keys.count.formatted()).font(.subheadline.weight(.medium))) \(noun_text)", comment: "Sentence composed of 2 variables to describe how many relay servers a user is connected. In source English, the first variable is the number of relay servers, and the second variable is 'Relay' or 'Relays'.")
                    if profile.pubkey == damus_state.pubkey && damus_state.is_privkey_user {
                        NavigationLink(value: Route.RelayConfig) {
                            relay_text
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        NavigationLink(value: Route.UserRelays(relays: Array(relays.keys).sorted())) {
                            relay_text
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            if profile.pubkey != damus_state.pubkey {
                let friended_followers = damus_state.contacts.get_friended_followers(profile.pubkey)
                if !friended_followers.isEmpty {
                    Spacer()

                    NavigationLink(value: Route.FollowersYouKnow(friendedFollowers: friended_followers, followers: followers)) {
                        HStack {
                            CondensedProfilePicturesView(state: damus_state, pubkeys: friended_followers, maxPictures: 3)
                            let followedByString = followedByString(txn: profile_txn, friended_followers, ndb: damus_state.ndb)
                            Text(followedByString)
                                .font(.subheadline).foregroundColor(.gray)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    var body: some View {
        ZStack {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    bannerSection
                        .zIndex(1)
                    
                    VStack() {
                        aboutSection

                        VStack(spacing: 0) {
                            CustomPicker(selection: $filter_state, content: {
                                Text("Notes", comment: "Label for filter for seeing only your notes (instead of notes and replies).").tag(FilterState.posts)
                                Text("Notes & Replies", comment: "Label for filter for seeing your notes and replies (instead of only your notes).").tag(FilterState.posts_and_replies)
                            })
                            Divider()
                                .frame(height: 1)
                        }
                        .background(colorScheme == .dark ? Color.black : Color.white)

                        if filter_state == FilterState.posts {
                            InnerTimelineView(events: profile.events, damus: damus_state, filter: content_filter(FilterState.posts))
                        }
                        if filter_state == FilterState.posts_and_replies {
                            InnerTimelineView(events: profile.events, damus: damus_state, filter: content_filter(FilterState.posts_and_replies))
                        }
                    }
                    .padding(.horizontal, Theme.safeAreaInsets?.left)
                    .zIndex(-yOffset > navbarHeight ? 0 : 1)
                }
            }
            .ignoresSafeArea()
            .navigationTitle("")
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    customNavbar
                }
            }
            .toolbarBackground(.hidden)
            .onReceive(handle_notify(.switched_timeline)) { _ in
                dismiss()
            }
            .onAppear() {
                check_nip05_validity(pubkey: self.profile.pubkey, profiles: self.damus_state.profiles)
                profile.subscribe()
                //followers.subscribe()
            }
            .onDisappear {
                profile.unsubscribe()
                followers.unsubscribe()
                // our profilemodel needs a bit more help
            }
            .sheet(isPresented: $show_share_sheet) {
                let url = URL(string: "https://damus.io/" + profile.pubkey.npub)!
                ShareSheet(activityItems: [url])
            }
            .fullScreenCover(isPresented: $show_qr_code) {
                QRCodeView(damus_state: damus_state, pubkey: profile.pubkey)
            }

            if damus_state.is_privkey_user {
                PostButtonContainer(is_left_handed: damus_state.settings.left_handed) {
                    notify(.compose(.posting(.user(profile.pubkey))))
                }
            }
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state
        ProfileView(damus_state: ds, pubkey: ds.pubkey)
    }
}

extension View {
    func profile_button_style(scheme: ColorScheme) -> some View {
        self.symbolRenderingMode(.palette)
            .font(.system(size: 32).weight(.thin))
            .foregroundStyle(scheme == .dark ? .white : .black, scheme == .dark ? .white : .black)
    }
}

@MainActor
func check_nip05_validity(pubkey: Pubkey, profiles: Profiles) {
    let profile_txn = profiles.lookup(id: pubkey)

    guard let profile = profile_txn.unsafeUnownedValue,
          let nip05 = profile.nip05,
          profiles.is_validated(pubkey) == nil
    else {
        return
    }

    Task.detached(priority: .background) {
        let validated = await validate_nip05(pubkey: pubkey, nip05_str: nip05)
        if validated != nil {
            print("validated nip05 for '\(nip05)'")
        }

        Task { @MainActor in
            profiles.set_validated(pubkey, nip05: validated)
            profiles.nip05_pubkey[nip05] = pubkey
            notify(.profile_updated(.remote(pubkey: pubkey)))
        }
    }
}
