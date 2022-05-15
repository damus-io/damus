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

func perform_follow_btn_action(_ fs: FollowState, target: String) -> FollowState {
    switch fs {
    case .follows:
        notify(.unfollow, target)
        return .following
    case .following:
        return .following
    case .unfollowing:
        return .following
    case .unfollows:
        notify(.follow, target)
        return .unfollowing
    }
}

struct ProfileView: View {
    let damus: DamusState
    
    @State var follow_state: FollowState = .follows
    @State private var selected_tab: ProfileTab = .posts
    @StateObject var profile: ProfileModel
    
    //@EnvironmentObject var profile: ProfileModel
    
    var TopSection: some View {
        VStack(alignment: .leading) {
            let data = damus.profiles.lookup(id: profile.pubkey)
            HStack(alignment: .top) {
                ProfilePicView(pubkey: profile.pubkey, size: PFP_SIZE!, highlight: .custom(Color.black, 2), image_cache: damus.image_cache, profiles: damus.profiles)
                
                Spacer()
                
                Button("\(follow_btn_txt(follow_state))") {
                    follow_state = perform_follow_btn_action(follow_state, target: profile.pubkey)
                }
                .buttonStyle(.bordered)
                .onReceive(handle_notify(.followed)) { notif in
                    let pk = notif.object as! String
                    if pk != profile.pubkey {
                        return
                    }
                    
                    self.follow_state = .follows
                }
                .onReceive(handle_notify(.unfollowed)) { notif in
                    let pk = notif.object as! String
                    if pk != profile.pubkey {
                        return
                    }
                    
                    self.follow_state = .unfollows
                }
            }
            
            if let pubkey = profile.pubkey {
                ProfileName(pubkey: pubkey, profile: data)
                    .font(.title)
                    //.border(Color.green)
                Text("\(pubkey)")
                    .textSelection(.enabled)
                    .font(.footnote)
                    .foregroundColor(id_to_color(pubkey))
            }
            Text(data?.about ?? "")
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            ScrollView {
                TopSection
            
                Divider()
                
                InnerTimelineView(events: $profile.events, damus: damus)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding([.leading, .trailing], 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        
        .navigationBarTitle("Profile")
        .onAppear() {
            follow_state = damus.contacts.follow_state(profile.pubkey)
            profile.subscribe()
        }
        .onDisappear {
            profile.unsubscribe()
            // our profilemodel needs a bit more help
        }
    }
}

/*
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
 */
