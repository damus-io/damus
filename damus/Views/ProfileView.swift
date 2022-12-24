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

func follow_btn_txt(_ fs: FollowState) -> String {
    switch fs {
    case .follows:
        return NSLocalizedString("Unfollow", comment: "Button to unfollow a user.")
    case .following:
        return NSLocalizedString("Following...", comment: "Label to indicate that the user is in the process of following another user.")
    case .unfollowing:
        return NSLocalizedString("Unfollowing...", comment: "Label to indicate that the user is in the process of unfollowing another user.")
    case .unfollows:
        return NSLocalizedString("Follow", comment: "Button to follow a user.")
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

struct ProfileNameView: View {
    let pubkey: String
    let profile: Profile?
    let damus: DamusState
    
    var body: some View {
        Group {
            if let real_name = profile?.display_name {
                VStack(alignment: .leading) {
                    Text(real_name)
                        .font(.title3.weight(.bold))
                    ProfileName(pubkey: pubkey, profile: profile, prefix: "@", damus: damus, show_friend_confirmed: true)
                        .font(.callout)
                        .foregroundColor(.gray)
                    KeyView(pubkey: pubkey)
                        .pubkey_context_menu(bech32_pubkey: pubkey)
                }
            } else {
                VStack(alignment: .leading) {
                    ProfileName(pubkey: pubkey, profile: profile, damus: damus, show_friend_confirmed: true)
                        .font(.title3.weight(.bold))
                    KeyView(pubkey: pubkey)
                        .pubkey_context_menu(bech32_pubkey: pubkey)
                }
            }
        }
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
        }
    }
    
    func fillColor() -> Color {
        colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite")
    }
    
    func borderColor() -> Color {
        colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite")
    }
}

struct ProfileView: View {
    let damus_state: DamusState
    let zoom_size: CGFloat = 350
    
    @State private var selected_tab: ProfileTab = .posts
    @StateObject var profile: ProfileModel
    @StateObject var followers: FollowersModel
    @State private var showingEditProfile = false
    @State var showing_select_wallet: Bool = false
    @State var is_zoomed: Bool = false
    @State var show_share_sheet: Bool = false
    @State var action_sheet_presented: Bool = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) var openURL

    // We just want to have a white "< Home" text here, however,
    // setting the initialiser is causing issues, and it's late.
    // Ref: https://blog.techchee.com/navigation-bar-title-style-color-and-custom-back-button-in-swiftui/
    /*
    init(damus_state: DamusState, zoom_size: CGFloat = 350) {
        self.damus_state = damus_state
        self.zoom_size = zoom_size
        Theme.navigationBarColors(background: nil, titleColor: .white, tintColor: nil)
    }*/
    
    func fillColor() -> Color {
        colorScheme == .light ? Color("DamusLightGrey") : Color("DamusDarkGrey")
    }
    
    func imageBorderColor() -> Color {
        colorScheme == .light ? Color("DamusWhite") : Color("DamusBlack")
    }
    
    func LNButton(lnurl: String, profile: Profile) -> some View {
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

    static let markdown = Markdown()
    
    var ActionSheetButton: some View {
        Button(action: {
            action_sheet_presented = true
        }) {
            Image(systemName: "ellipsis.circle")
                .profile_button_style(scheme: colorScheme)
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
    
    var ShareButton: some View {
        Button(action: {
            show_share_sheet = true
        }) {
            Image(systemName: "square.and.arrow.up.circle")
                .profile_button_style(scheme: colorScheme)
        }
    }
    
    var DMButton: some View {
        let dm_model = damus_state.dms.lookup_or_create(profile.pubkey)
        let dmview = DMChatView(damus_state: damus_state, pubkey: profile.pubkey)
            .environmentObject(dm_model)
        return NavigationLink(destination: dmview) {
            Image(systemName: "bubble.left.circle")
                .profile_button_style(scheme: colorScheme)
        }
    }

    private func getScrollOffset(_ geometry: GeometryProxy) -> CGFloat {
        geometry.frame(in: .global).minY
    }

    private func getHeightForHeaderImage(_ geometry: GeometryProxy) -> CGFloat {
        let offset = getScrollOffset(geometry)
        let imageHeight = 150.0

        if offset > 0 {
            return imageHeight + offset
        }

        return imageHeight
    }

    private func getOffsetForHeaderImage(_ geometry: GeometryProxy) -> CGFloat {
        let offset = getScrollOffset(geometry)

        // Image was pulled down
        if offset > 0 {
            return -offset
        }

        return 0
    }
    
    var TopSection: some View {
        ZStack(alignment: .top) {
            GeometryReader { geometry in
                BannerImageView(pubkey: profile.pubkey, profiles: damus_state.profiles)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: self.getHeightForHeaderImage(geometry))
                    .clipped()
                    .offset(x: 0, y: self.getOffsetForHeaderImage(geometry))

            }.frame(height: BANNER_HEIGHT)
            
            VStack(alignment: .leading, spacing: 8.0) {
                let data = damus_state.profiles.lookup(id: profile.pubkey)
                let pfp_size: CGFloat = 90.0
                
                HStack(alignment: .center) {
                    ProfilePicView(pubkey: profile.pubkey, size: pfp_size, highlight: .custom(imageBorderColor(), 4.0), profiles: damus_state.profiles, contacts: damus_state.contacts)
                        .onTapGesture {
                            is_zoomed.toggle()
                        }
                        .fullScreenCover(isPresented: $is_zoomed) {
                            ProfileZoomView(pubkey: profile.pubkey, profiles: damus_state.profiles, contacts: damus_state.contacts)}
                        .offset(y: -(pfp_size/2.0)) // Increase if set a frame
                    
                    Spacer()
                    
                    Group {
                        ActionSheetButton
                        
                        if let profile = data {
                            if let lnurl = profile.lnurl, lnurl != "" {
                                LNButton(lnurl: lnurl, profile: profile)
                            }
                        }
                        
                        DMButton
                        
                        if profile.pubkey != damus_state.pubkey {
                            FollowButtonView(
                                target: profile.get_follow_target(),
                                follow_state: damus_state.contacts.follow_state(profile.pubkey)
                            )
                        } else if damus_state.keypair.privkey != nil {
                            NavigationLink(destination: EditMetadataView(damus_state: damus_state)) {
                                EditButton(damus_state: damus_state)
                            }
                        }
                        
                    }
                    .offset(y: -15.0) // Increase if set a frame
                    
                }
                               
                ProfileNameView(pubkey: profile.pubkey, profile: data, damus: damus_state)
                    //.padding(.bottom)
                    .padding(.top,-(pfp_size/2.0))
                
                Text(ProfileView.markdown.process(data?.about ?? ""))
                    .font(.subheadline).textSelection(.enabled)
                
                if let url = data?.website_url {
                    WebsiteLink(url: url)
                }
                
                Divider()
                
                HStack {
                    if let contact = profile.contacts {
                        let contacts = contact.referenced_pubkeys.map { $0.ref_id }
                        let following_model = FollowingModel(damus_state: damus_state, contacts: contacts)
                        NavigationLink(destination: FollowingView(damus_state: damus_state, following: following_model, whos: profile.pubkey)) {
                            HStack {
                                Text("\(Text("\(profile.following)", comment: "Number of profiles a user is following.").font(.subheadline.weight(.medium))) \(Text("Following", comment: "Part of a larger sentence to describe how many profiles a user is following.").font(.subheadline).foregroundColor(.gray))", comment: "Sentence composed of 2 variables to describe how many profiles a user is following. In source English, the first variable is the number of profiles being followed, and the second variable is 'Following'.")
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    let fview = FollowersView(damus_state: damus_state, whos: profile.pubkey)
                        .environmentObject(followers)
                    if followers.contacts != nil {
                        NavigationLink(destination: fview) {
                            FollowersCount
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        FollowersCount
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                followers.contacts = []
                                followers.subscribe()
                            }
                    }
                    
                    if let relays = profile.relays {
                        NavigationLink(destination: UserRelaysView(state: damus_state, pubkey: profile.pubkey, relays: Array(relays.keys).sorted())) {
                            Text("\(Text("\(relays.keys.count)", comment: "Number of relay servers a user is connected.").font(.subheadline.weight(.medium))) \(Text(String(format: NSLocalizedString("relays_count", comment: "Part of a larger sentence to describe how many relay servers a user is connected."), relays.keys.count)).font(.subheadline).foregroundColor(.gray))", comment: "Sentence composed of 2 variables to describe how many relay servers a user is connected. In source English, the first variable is the number of relay servers, and the second variable is 'Relay' or 'Relays'.")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal,18)
            //.offset(y:120)
            .padding(.top,150)
        }
    }
    
    var FollowersCount: some View {
        HStack {
            if followers.count == nil {
                Image(systemName: "square.and.arrow.down")
                Text("Followers", comment: "Label describing followers of a user.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            } else {
                let followerCount = followers.count!
                Text("\(Text("\(followerCount)", comment: "Number of people following a user.").font(.subheadline.weight(.medium))) \(Text(String(format: NSLocalizedString("followers_count", comment: "Part of a larger sentence to describe how many people are following a user."), followerCount)).font(.subheadline).foregroundColor(.gray))", comment: "Sentence composed of 2 variables to describe how many people are following a user. In source English, the first variable is the number of followers, and the second variable is 'Follower' or 'Followers'.")
            }
        }
    }
        
    var body: some View {
        
        VStack(alignment: .leading) {
            ScrollView {
                TopSection
            
                Divider()
                
                InnerTimelineView(events: $profile.events, damus: damus_state, show_friend_icon: false, filter: { _ in true })
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        .ignoresSafeArea()
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
    
    var body: some View {
        let bech32 = bech32_pubkey(pubkey) ?? pubkey
        
        HStack {
            RoundedRectangle(cornerRadius: 24)
                .frame(width: 275, height:22)
                .foregroundColor(fillColor())
                .overlay(
                    HStack {
                        Button {
                            UIPasteboard.general.string = bech32
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            isCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                isCopied = false
                            }
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
                            .offset(x:-3) // Not sure why this is needed.
                    }
                )
            if isCopied != true {
                Button {
                    UIPasteboard.general.string = bech32
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        isCopied = false
                    }
                } label: {
                    Label {
                        Text("Public key", comment: "Label indicating that the text is a user's public account key.")
                    } icon: {
                        Image("ic-copy")
                            .contentShape(Rectangle())
                            .frame(width: 20, height: 20)
                    }
                    .labelStyle(IconOnlyLabelStyle())
                    .symbolRenderingMode(.hierarchical)
                }
            } else {
                HStack {
                    Image("ic-tick")
                        .frame(width: 20, height: 20)
                    Text(NSLocalizedString("Copied", comment: "Label indicating that a user's key was copied."))
                        .font(.footnote)
                        .foregroundColor(Color("DamusGreen"))
                }
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
