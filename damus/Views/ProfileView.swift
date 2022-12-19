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
        return "Unfollow"
    case .following:
        return "Following..."
    case .unfollowing:
        return "Unfollowing..."
    case .unfollows:
        return "Follow"
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

struct ProfileView: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    let damus_state: DamusState
    
    @State private var selected_tab: ProfileTab = .posts
    @StateObject var profile: ProfileModel
    @StateObject var followers: FollowersModel
    
    @Environment(\.dismiss) var dismiss
    
    //@EnvironmentObject var profile: ProfileModel
    
    func LNButton(_ url: URL) -> some View {
        Button(action: {
            UIApplication.shared.open(url)
        }) {
            Image(systemName: "bolt.circle")
                .symbolRenderingMode(.palette)
                .font(.system(size: 34).weight(.thin))
                .foregroundStyle(colorScheme == .light ? .black : .white, colorScheme == .light ? .black.opacity(0.1) : .white.opacity(0.2))
        }
    }
    
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
                ProfilePicView(pubkey: profile.pubkey, size: PFP_SIZE, highlight: .custom(Color.black, 2), profiles: damus_state.profiles)
                
                Spacer()
                
                if let lnuri = data?.lightning_uri {
                    LNButton(lnuri)
                }
                
                DMButton
                
                FollowButtonView(target: profile.get_follow_target(), follow_state: damus_state.contacts.follow_state(profile.pubkey))
            }
            
            ProfileNameView(pubkey: profile.pubkey, profile: data, contacts: damus_state.contacts)
                .padding(.bottom)
            
            Text(data?.about ?? "")
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
                NavigationLink(destination: fview) {
                    HStack {
                        Text("\(followers.contacts.count)")
                            .font(.subheadline.weight(.medium))
                        Text("Followers")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
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
            followers.subscribe()
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
    
    let prof = Profile(name: "damus", display_name: "Damus", about: "iOS app!", picture: "https://damus.io/img/logo.png", website: "https://damus.io", lud06: nil, lud16: "jb55@sendsats.lol")
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

        
