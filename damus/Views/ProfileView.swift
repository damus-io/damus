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

struct ProfileView: View {
    let damus: DamusState
    
    @State private var selected_tab: ProfileTab = .posts
    @StateObject var profile: ProfileModel
    
    //@EnvironmentObject var profile: ProfileModel
    @EnvironmentObject var profiles: Profiles
    
    var TopSection: some View {
        HStack(alignment: .top) {
            let data = profiles.lookup(id: profile.pubkey)
            ProfilePicView(picture: data?.picture, size: 64, highlight: .custom(Color.black, 4), image_cache: damus.image_cache)
                //.border(Color.blue)
            VStack(alignment: .leading) {
                if let pubkey = profile.pubkey {
                    ProfileName(pubkey: pubkey, profile: data)
                        .font(.title)
                        //.border(Color.green)
                }
                Text(data?.about ?? "")
                    //.border(Color.red)
            }
            //.border(Color.purple)
            //Spacer()
        }
        //.border(Color.indigo)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            TopSection
            Picker("", selection: $selected_tab) {
                Text("Posts").tag(ProfileTab.posts)
                Text("Following").tag(ProfileTab.following)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            Divider()

            Group {
                switch(selected_tab) {
                case .posts:
                    TimelineView(events: $profile.events, damus: damus)
                            .environmentObject(profiles)
                case .following:
                        Text("Following")
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        //.border(Color.white)
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
