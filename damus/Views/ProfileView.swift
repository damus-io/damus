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
            Text("Edit")
                .frame(height: 30)
                .padding(.horizontal,25)
                .font(.caption.weight(.bold))
                .foregroundColor(fillColor())
                .cornerRadius(24)
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(borderColor(), lineWidth: 1)
                }
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
    @StateObject var user_settings = UserSettingsStore()
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
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
            if user_settings.show_wallet_selector  {
                showing_select_wallet = true
            } else {
                open_with_wallet(wallet: user_settings.default_wallet.model, invoice: lnurl)
            }
        }) {
            Image(systemName: "bolt.circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(colorScheme == .dark ? .white : .black, colorScheme == .dark ? .white : .black)
                .font(.system(size: 32).weight(.thin))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = profile.lnurl ?? ""
                    } label: {
                        Label("Copy LNUrl", systemImage: "doc.on.doc")
                    }
                }
            
        }
        .cornerRadius(24)
        .sheet(isPresented: $showing_select_wallet, onDismiss: {showing_select_wallet = false}) {
            SelectWalletView(showingSelectWallet: $showing_select_wallet, invoice: lnurl)
                .environmentObject(user_settings)
        }
    }

    static let markdown = Markdown()

    var DMButton: some View {
        let dm_model = damus_state.dms.lookup_or_create(profile.pubkey)
        let dmview = DMChatView(damus_state: damus_state, pubkey: profile.pubkey)
            .environmentObject(dm_model)
        return NavigationLink(destination: dmview) {
            Image(systemName: "bubble.left.circle")
                .symbolRenderingMode(.palette)
                .font(.system(size: 32).weight(.thin))
                .foregroundStyle(colorScheme == .dark ? .white : .black, colorScheme == .dark ? .white : .black)
        }
    }

    private func getScrollOffset(_ geometry: GeometryProxy) -> CGFloat {
        geometry.frame(in: .global).minY
    }

    private func getHeightForHeaderImage(_ geometry: GeometryProxy) -> CGFloat {
        let offset = getScrollOffset(geometry)
        let imageHeight = geometry.size.height

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
                Image("profile-banner")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: self.getHeightForHeaderImage(geometry))
                    .offset(x: 0, y: self.getOffsetForHeaderImage(geometry))
            }.frame(height: 150)
            VStack(alignment: .leading) {
                let data = damus_state.profiles.lookup(id: profile.pubkey)
                let pfp_size: CGFloat = 90.0
                
                HStack(alignment: .center) {
                    ProfilePicView(pubkey: profile.pubkey, size: pfp_size, highlight: .custom(imageBorderColor(), 4.0), profiles: damus_state.profiles)
                        .onTapGesture {
                            is_zoomed.toggle()
                        }
                        .sheet(isPresented: $is_zoomed) {
                            ProfilePicView(pubkey: profile.pubkey, size: zoom_size, highlight: .none, profiles: damus_state.profiles)
                        }
                        .offset(y: -(pfp_size/2.0)) // Increase if set a frame
                        
                    Spacer()
                    
                    Group {
                        
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
                    .font(.subheadline)
                
                Divider()
                
                HStack {
                    if let contact = profile.contacts {
                        let contacts = contact.referenced_pubkeys.map { $0.ref_id }
                        let following_model = FollowingModel(damus_state: damus_state, contacts: contacts)
                        NavigationLink(destination: FollowingView(damus_state: damus_state, following: following_model, whos: profile.pubkey)) {
                            HStack {
                                Text("\(profile.following)")
                                    .font(.subheadline.weight(.medium))
                                Text("Following")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
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
                            Text("\(relays.keys.count)")
                                .font(.subheadline.weight(.medium))
                            Text("Relays")
                                .font(.subheadline)
                                .foregroundColor(.gray)
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
            if followers.count_display == "?" {
                Image(systemName: "square.and.arrow.down")
            } else {
                Text("\(followers.count_display)")
                    .font(.subheadline.weight(.medium))
            }
            Text("Followers")
                .font(.subheadline)
                .foregroundColor(.gray)
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
    let damus = DamusState(pool: RelayPool(), keypair: Keypair(pubkey: pubkey, privkey: "privkey"), likes: EventCounter(our_pubkey: pubkey), boosts: EventCounter(our_pubkey: pubkey), contacts: Contacts(our_pubkey: pubkey), tips: TipCounter(our_pubkey: pubkey), profiles: Profiles(), dms: DirectMessagesModel(), previews: PreviewCache())
    
    let prof = Profile(name: "damus", display_name: "damus", about: "iOS app!", picture: "https://damus.io/img/logo.png", website: "https://damus.io", lud06: nil, lud16: "jb55@sendsats.lol", nip05: "damus.io")
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
                            Label {
                                Text("Public key")
                            } icon: {
                                Image("ic-key")
                                    .contentShape(Rectangle())
                                    .frame(width: 16, height: 16)
                            }
                            .labelStyle(IconOnlyLabelStyle())
                            .symbolRenderingMode(.hierarchical)
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
                        Text("Public key")
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
                    Text("Copied")
                        .font(.footnote)
                        .foregroundColor(Color("DamusGreen"))
                }
            }
        }
    }
}
