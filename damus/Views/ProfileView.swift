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
    let damus_state: DamusState
    
    @State private var selected_tab: ProfileTab = .posts
    @StateObject var profile: ProfileModel
    
    //@EnvironmentObject var profile: ProfileModel
    
    var TopSection: some View {
        VStack(alignment: .leading) {
            let data = damus_state.profiles.lookup(id: profile.pubkey)
            HStack(alignment: .top) {
                ProfilePicView(pubkey: profile.pubkey, size: PFP_SIZE, highlight: .custom(Color.black, 2), image_cache: damus_state.image_cache, profiles: damus_state.profiles)
                
                Spacer()
                
                FollowButtonView(pubkey: profile.pubkey, follow_state: damus_state.contacts.follow_state(profile.pubkey))
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
            
            if let contact = profile.contacts {
                Divider()
                
                NavigationLink(destination: FollowingView(contact: contact, damus_state: damus_state)) {
                    HStack {
                        Text("\(profile.following)")
                        Text("Following")
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
            
                Divider()
                
                InnerTimelineView(events: $profile.events, damus: damus_state)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding([.leading, .trailing], 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        
        .navigationBarTitle("Profile")
        .onAppear() {
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
