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
        VStack{
            let data = profiles.lookup(id: profile.pubkey)
            HStack {
                ProfilePicView(pubkey: profile.pubkey, size: PFP_SIZE!, highlight: .custom(Color.black, 2), image_cache: damus.image_cache)
                    .environmentObject(profiles)
                
                Spacer()
                
                Button("Follow") {
                    print("follow \(profile.pubkey)")
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
                    .environmentObject(profiles)
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
