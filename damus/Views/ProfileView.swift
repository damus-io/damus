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
    let contacts: Contacts
    
    var body: some View {
        Group {
            if let real_name = profile?.display_name {
                VStack(alignment: .leading) {
                    HStack {
                        Text(real_name)
                            .font(.title3.weight(.bold))
                        
                        KeyView(pubkey: pubkey)
                            .pubkey_context_menu(bech32_pubkey: pubkey)
                    }
                    ProfileName(pubkey: pubkey, profile: profile, prefix: "@", contacts: contacts, show_friend_confirmed: true)
                        .font(.callout)
                        .foregroundColor(.gray)
                }
            } else {
                HStack {
                    ProfileName(pubkey: pubkey, profile: profile, contacts: contacts, show_friend_confirmed: true)
                    
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
                .padding(.horizontal, 25)
                .padding(.vertical, 10)
                .font(.caption.weight(.bold))
                .foregroundColor(fillColor())
                .background(emptyColor())
                .cornerRadius(20)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor(), lineWidth: 1)
                }
        }
    }
    
    func fillColor() -> Color {
        colorScheme == .light ? .black : .white
    }
    
    func emptyColor() -> Color {
        colorScheme == .light ? .white : .black
    }
    
    func borderColor() -> Color {
        colorScheme == .light ? .black.opacity(0.1) : .white.opacity(0.2)
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
    
    //@EnvironmentObject var profile: ProfileModel
    
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
                .font(.system(size: 34).weight(.thin))
                .foregroundStyle(colorScheme == .light ? .black : .white, colorScheme == .light ? .black.opacity(0.1) : .white.opacity(0.2))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = profile.lnurl ?? ""
                    } label: {
                        Label("Copy LNURL", systemImage: "doc.on.doc")
                    }
                }
        }.sheet(isPresented: $showing_select_wallet, onDismiss: {showing_select_wallet = false}) {
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
                .font(.system(size: 34).weight(.thin))
                .foregroundStyle(colorScheme == .light ? .black : .white, colorScheme == .light ? .black.opacity(0.1) : .white.opacity(0.2))
        }
    }
    
    var TopSection: some View {
        VStack(alignment: .leading) {
            let data = damus_state.profiles.lookup(id: profile.pubkey)
            
            HStack(alignment: .center) {
                ProfilePicView(pubkey: profile.pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles)
                    .onTapGesture {
                        is_zoomed.toggle()
                    }
                    .sheet(isPresented: $is_zoomed) {
                        ProfilePicView(pubkey: profile.pubkey, size: zoom_size, highlight: .none, profiles: damus_state.profiles)
                    }
                
                Spacer()

                if let profile = data {
                    if let lnurl = profile.lnurl {
                        LNButton(lnurl: lnurl, profile: profile)
                    }
                }
                
                DMButton
                
                if profile.pubkey != damus_state.pubkey {
                    FollowButtonView(
                        target: profile.get_follow_target(),
                        follow_state: damus_state.contacts.follow_state(profile.pubkey)
                    )
                } else {
                    NavigationLink(destination: EditMetadataView(damus_state: damus_state)) {
                        EditButton(damus_state: damus_state)
                    }
                }
                
            }
            
            ProfileNameView(pubkey: profile.pubkey, profile: data, contacts: damus_state.contacts)
                .padding(.bottom)
            
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
    }
    
    var FollowersCount: some View {
        HStack {
            Text("\(followers.count_display)")
                .font(.subheadline.weight(.medium))
            Text("Followers")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            ScrollView {
                TopSection
                    .padding(.horizontal)
            
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
    let damus = DamusState(pool: RelayPool(), keypair: Keypair(pubkey: pubkey, privkey: "privkey"), likes: EventCounter(our_pubkey: pubkey), boosts: EventCounter(our_pubkey: pubkey), contacts: Contacts(), tips: TipCounter(our_pubkey: pubkey), profiles: Profiles(), dms: DirectMessagesModel())
    
    let prof = Profile(name: "damus", display_name: "Damus", about: "iOS app!", picture: "https://damus.io/img/logo.png", website: "https://damus.io", lud06: nil, lud16: "jb55@sendsats.lol", nip05: "damus.io")
    let tsprof = TimestampedProfile(profile: prof, timestamp: 0)
    damus.profiles.add(id: pubkey, profile: tsprof)
    return damus
}

struct KeyView: View {
    let pubkey: String
    
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isCopied = false
    
    var body: some View {
        let col = id_to_color(pubkey)
        let bech32 = bech32_pubkey(pubkey) ?? pubkey
        
        Button {
            UIPasteboard.general.string = bech32
            isCopied = true
        } label: {
            Label(isCopied ? "Copied" : "", systemImage: "key.fill")
                .font(isCopied ? .caption : .system(size: 15).weight(.light))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(isCopied ? .gray : col)
        }
    }
}

        
