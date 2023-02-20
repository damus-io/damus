//
//  ProfileView.swift
//  damus
//
//  Created by William Casarin on 2022-04-23.
//

import SwiftUI

enum ProfileTab: Hashable {
    case posts
    case following
}

enum FollowState {
    case follows
    case following
    case unfollowing
    case unfollows
}

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

func follow_btn_enabled_state(_ fs: FollowState) -> Bool {
    switch fs {
    case .follows:
        return true
    case .following:
        return false
    case .unfollowing:
        return false
    case .unfollows:
       return true
    }
}

struct EditButton: View {
    let damus_state: DamusState
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationLink(destination: EditMetadataView(damus_state: damus_state)) {
            Text("Edit", comment: "Button to edit user's profile.")
                .frame(height: 30)
                .padding(.horizontal,25)
                .font(.caption.weight(.bold))
                .foregroundColor(fillColor())
                .cornerRadius(24)
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(borderColor(), lineWidth: 1)
                }
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }
    
    func fillColor() -> Color {
        colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite")
    }
    
    func borderColor() -> Color {
        colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite")
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
    
    static let markdown = Markdown()
    
    @State private var selected_tab: ProfileTab = .posts
    @StateObject var profile: ProfileModel
    @StateObject var followers: FollowersModel
    @State private var showingEditProfile = false
    @State var showing_select_wallet: Bool = false
    @State var is_zoomed: Bool = false
    @State var show_share_sheet: Bool = false
    @State var action_sheet_presented: Bool = false
    @State var filter_state : FilterState = .posts
    @State var yOffset: CGFloat = 0
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) var openURL
    @Environment(\.presentationMode) var presentationMode
    
    func fillColor() -> Color {
        colorScheme == .light ? Color("DamusLightGrey") : Color("DamusDarkGrey")
    }
    
    func imageBorderColor() -> Color {
        colorScheme == .light ? Color("DamusWhite") : Color("DamusBlack")
    }
    
    func bannerBlurViewOpacity() -> Double  {
        let progress = -(yOffset + navbarHeight) / 100
        return Double(-yOffset > navbarHeight ? progress : 0)
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
                        BannerImageView(pubkey: profile.pubkey, profiles: damus_state.profiles)
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
    }
    
    var navbarHeight: CGFloat {
        return 100.0 - (Theme.safeAreaInsets?.top ?? 0)
    }
    
    @ViewBuilder
    func navImage(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .frame(width: 33, height: 33)
            .background(Color.black.opacity(0.6))
            .clipShape(Circle())
    }
    
    var navBackButton: some View {
        Button {
            presentationMode.wrappedValue.dismiss()
        } label: {
            navImage(systemImage: "chevron.left")
        }
    }
    
    var navActionSheetButton: some View {
        Button(action: {
            action_sheet_presented = true
        }) {
            navImage(systemImage: "ellipsis")
        }
        .confirmationDialog(NSLocalizedString("Actions", comment: "Title for confirmation dialog to either share, report, or block a profile."), isPresented: $action_sheet_presented) {
            Button(NSLocalizedString("Share", comment: "Button to share the link to a profile.")) {
                show_share_sheet = true
            }

            // Only allow reporting if logged in with private key and the currently viewed profile is not the logged in profile.
            if profile.pubkey != damus_state.pubkey && damus_state.is_privkey_user {
                Button(NSLocalizedString("Report", comment: "Button to report a profile."), role: .destructive) {
                    let target: ReportTarget = .user(profile.pubkey)
                    notify(.report, target)
                }

                Button(NSLocalizedString("Block", comment: "Button to block a profile."), role: .destructive) {
                    notify(.block, profile.pubkey)
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
        .padding(.horizontal)
        .accentColor(Color("DamusWhite"))
    }
    
    func lnButton(lnurl: String, profile: Profile) -> some View {
        Button(action: {
            if damus_state.settings.show_wallet_selector  {
                showing_select_wallet = true
            } else {
                open_with_wallet(wallet: damus_state.settings.default_wallet.model, invoice: lnurl)
            }
        }) {
            Image(systemName: "bolt.circle")
                .profile_button_style(scheme: colorScheme)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = profile.lnurl ?? ""
                    } label: {
                        Label(NSLocalizedString("Copy LNURL", comment: "Context menu option for copying a user's Lightning URL."), systemImage: "doc.on.doc")
                    }
                }
            
        }
        .cornerRadius(24)
        .sheet(isPresented: $showing_select_wallet, onDismiss: {showing_select_wallet = false}) {
            SelectWalletView(showingSelectWallet: $showing_select_wallet, our_pubkey: damus_state.pubkey, invoice: lnurl)
        }
    }
    
    var dmButton: some View {
        let dm_model = damus_state.dms.lookup_or_create(profile.pubkey)
        let dmview = DMChatView(damus_state: damus_state, pubkey: profile.pubkey)
            .environmentObject(dm_model)
        return NavigationLink(destination: dmview) {
            Image(systemName: "bubble.left.circle")
                .profile_button_style(scheme: colorScheme)
        }
    }
    
    func actionSection(profile_data: Profile?) -> some View {
        return Group {
            
            if let profile = profile_data {
                if let lnurl = profile.lnurl, lnurl != "" {
                    lnButton(lnurl: lnurl, profile: profile)
                }
            }
            
            dmButton
            
            if profile.pubkey != damus_state.pubkey {
                FollowButtonView(
                    target: profile.get_follow_target(),
                    follows_you: profile.follows(pubkey: damus_state.pubkey),
                    follow_state: damus_state.contacts.follow_state(profile.pubkey)
                )
            } else if damus_state.keypair.privkey != nil {
                NavigationLink(destination: EditMetadataView(damus_state: damus_state)) {
                    EditButton(damus_state: damus_state)
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
    
    func nameSection(profile_data: Profile?) -> some View {
        return Group {
            HStack(alignment: .center) {
                ProfilePicView(pubkey: profile.pubkey, size: pfp_size, highlight: .custom(imageBorderColor(), 4.0), profiles: damus_state.profiles)
                    .padding(.top, -(pfp_size / 2.0))
                    .offset(y: pfpOffset())
                    .scaleEffect(pfpScale())
                    .onTapGesture {
                        is_zoomed.toggle()
                    }
                    .fullScreenCover(isPresented: $is_zoomed) {
                        ProfileZoomView(pubkey: profile.pubkey, profiles: damus_state.profiles)                        }
                
                Spacer()
                
                actionSection(profile_data: profile_data)
            }
            
            let follows_you = profile.follows(pubkey: damus_state.pubkey)
            ProfileNameView(pubkey: profile.pubkey, profile: profile_data, follows_you: follows_you, damus: damus_state)
        }
    }
    
    var followersCount: some View {
        HStack {
            if followers.count == nil {
                Image(systemName: "square.and.arrow.down")
                Text("Followers", comment: "Label describing followers of a user.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            } else {
                let followerCount = followers.count!
                Text("\(Text(verbatim: "\(followerCount)").font(.subheadline.weight(.medium))) \(Text(String(format: NSLocalizedString("followers_count", comment: "Part of a larger sentence to describe how many people are following a user."), followerCount)).font(.subheadline).foregroundColor(.gray))", comment: "Sentence composed of 2 variables to describe how many people are following a user. In source English, the first variable is the number of followers, and the second variable is 'Follower' or 'Followers'.")
            }
        }
    }
    
    var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            let profile_data = damus_state.profiles.lookup(id: profile.pubkey)
            
            nameSection(profile_data: profile_data)
            
            Text(ProfileView.markdown.process(profile_data?.about ?? ""))
                .font(.subheadline).textSelection(.enabled)
            
            if let url = profile_data?.website_url {
                WebsiteLink(url: url)
            }
            
            HStack {
                if let contact = profile.contacts {
                    let contacts = contact.referenced_pubkeys.map { $0.ref_id }
                    let following_model = FollowingModel(damus_state: damus_state, contacts: contacts)
                    NavigationLink(destination: FollowingView(damus_state: damus_state, following: following_model, whos: profile.pubkey)) {
                        HStack {
                            Text("\(Text(verbatim: "\(profile.following)").font(.subheadline.weight(.medium))) \(Text("Following", comment: "Part of a larger sentence to describe how many profiles a user is following.").font(.subheadline).foregroundColor(.gray))", comment: "Sentence composed of 2 variables to describe how many profiles a user is following. In source English, the first variable is the number of profiles being followed, and the second variable is 'Following'.")
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                let fview = FollowersView(damus_state: damus_state, whos: profile.pubkey)
                    .environmentObject(followers)
                if followers.contacts != nil {
                    NavigationLink(destination: fview) {
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
                    let relay_text = Text("\(Text(verbatim: "\(relays.keys.count)").font(.subheadline.weight(.medium))) \(Text(String(format: NSLocalizedString("relays_count", comment: "Part of a larger sentence to describe how many relay servers a user is connected."), relays.keys.count)).font(.subheadline).foregroundColor(.gray))", comment: "Sentence composed of 2 variables to describe how many relay servers a user is connected. In source English, the first variable is the number of relay servers, and the second variable is 'Relay' or 'Relays'.")
                    if profile.pubkey == damus_state.pubkey && damus_state.is_privkey_user {
                        NavigationLink(destination: RelayConfigView(state: damus_state)) {
                            relay_text
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        NavigationLink(destination: UserRelaysView(state: damus_state, pubkey: profile.pubkey, relays: Array(relays.keys).sorted())) {
                            relay_text
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal)
    }
        
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                bannerSection
                    .zIndex(1)
                
                VStack() {
                    aboutSection
                
                    VStack(spacing: 0) {
                        CustomPicker(selection: $filter_state, content: {
                            Text("Posts", comment: "Label for filter for seeing only your posts (instead of posts and replies).").tag(FilterState.posts)
                            Text("Posts & Replies", comment: "Label for filter for seeing your posts and replies (instead of only your posts).").tag(FilterState.posts_and_replies)
                        })
                        Divider()
                            .frame(height: 1)
                    }
                    .background(colorScheme == .dark ? Color.black : Color.white)
                    
                    if filter_state == FilterState.posts {
                        InnerTimelineView(events: profile.events, damus: damus_state, show_friend_icon: false, filter: FilterState.posts.filter)
                    }
                    if filter_state == FilterState.posts_and_replies {
                        InnerTimelineView(events: profile.events, damus: damus_state, show_friend_icon: false, filter: FilterState.posts_and_replies.filter)
                    }
                }
                .padding(.horizontal, Theme.safeAreaInsets?.left)
                .zIndex(-yOffset > navbarHeight ? 0 : 1)
            }
        }
        .ignoresSafeArea()
        .navigationTitle("")
        .navigationBarHidden(true)
        .overlay(customNavbar, alignment: .top)
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
        .onAppear() {
            profile.subscribe()
            //followers.subscribe()
        }
        .onDisappear {
            profile.unsubscribe()
            followers.unsubscribe()
            // our profilemodel needs a bit more help
        }
        .sheet(isPresented: $show_share_sheet) {
            if let npub = bech32_pubkey(profile.pubkey) {
                if let url = URL(string: "https://damus.io/" + npub) {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        let followers = FollowersModel(damus_state: ds, target: ds.pubkey)
        let profile_model = ProfileModel(pubkey: ds.pubkey, damus: ds)
        ProfileView(damus_state: ds, profile: profile_model, followers: followers)
    }
}

func test_damus_state() -> DamusState {
    let pubkey = "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"
    let damus = DamusState.empty
    
    let prof = Profile(name: "damus", display_name: "damus", about: "iOS app!", picture: "https://damus.io/img/logo.png", banner: "", website: "https://damus.io", lud06: nil, lud16: "jb55@sendsats.lol", nip05: "damus.io")
    let tsprof = TimestampedProfile(profile: prof, timestamp: 0)
    damus.profiles.add(id: pubkey, profile: tsprof)
    return damus
}

struct KeyView: View {
    let pubkey: String
    
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isCopied = false
    
    func fillColor() -> Color {
        colorScheme == .light ? Color("DamusLightGrey") : Color("DamusDarkGrey")
    }
    
    func keyColor() -> Color {
        colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite")
    }
    
    private func copyPubkey(_ pubkey: String) {
        UIPasteboard.general.string = pubkey
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation {
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    isCopied = false
                }
            }
        }
    }
    
    var body: some View {
        let bech32 = bech32_pubkey(pubkey) ?? pubkey
        
        HStack {
            RoundedRectangle(cornerRadius: 11)
                .frame(height: 22)
                .foregroundColor(fillColor())
                .overlay(
                    HStack {
                        Button {
                            copyPubkey(bech32)
                        } label: {
                            Label(NSLocalizedString("Public Key", comment: "Label indicating that the text is a user's public account key."), systemImage: "key.fill")
                                .font(.custom("key", size: 12.0))
                                .labelStyle(IconOnlyLabelStyle())
                                .foregroundStyle(hex_to_rgb(pubkey))
                                .symbolRenderingMode(.palette)
                        }
                        .padding(.leading,4)
                        Text(abbrev_pubkey(bech32, amount: 16))
                            .font(.footnote)
                            .foregroundColor(keyColor())
                    }
                )
            if isCopied != true {
                Button {
                    copyPubkey(bech32)
                } label: {
                    Label {
                        Text("Public key", comment: "Label indicating that the text is a user's public account key.")
                    } icon: {
                        Image(systemName: "square.on.square.dashed")
                            .contentShape(Rectangle())
                            .foregroundColor(.gray)
                            .frame(width: 20, height: 20)
                    }
                    .labelStyle(IconOnlyLabelStyle())
                    .symbolRenderingMode(.hierarchical)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .frame(width: 20, height: 20)
                    Text(NSLocalizedString("Copied", comment: "Label indicating that a user's key was copied."))
                        .font(.footnote)
                        .layoutPriority(1)
                }
                .foregroundColor(Color("DamusGreen"))
            }
        }
    }
}

extension View {
    func profile_button_style(scheme: ColorScheme) -> some View {
        self.symbolRenderingMode(.palette)
            .font(.system(size: 32).weight(.thin))
            .foregroundStyle(scheme == .dark ? .white : .black, scheme == .dark ? .white : .black)
    }
}
