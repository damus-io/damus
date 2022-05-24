//
//  FollowingView.swift
//  damus
//
//  Created by William Casarin on 2022-05-16.
//

import SwiftUI

struct FollowUserView: View {
    let target: FollowTarget
    let damus_state: DamusState
    
    var body: some View {
        HStack(alignment: .top) {
            let pmodel = ProfileModel(pubkey: target.pubkey, damus: damus_state)
            let pv = ProfileView(damus_state: damus_state, profile: pmodel)
            
            NavigationLink(destination: pv) {
                ProfilePicView(pubkey: target.pubkey, size: PFP_SIZE, highlight: .none, image_cache: damus_state.image_cache, profiles: damus_state.profiles)
            }
            
            VStack(alignment: .leading) {
                let profile = damus_state.profiles.lookup(id: target.pubkey)
                ProfileName(pubkey: target.pubkey, profile: profile)
                if let about = profile.flatMap { $0.about } {
                    Text(about)
                }
            }
            
            Spacer()
            
            FollowButtonView(target: target, follow_state: damus_state.contacts.follow_state(target.pubkey))
        }
    }
}

struct FollowingView: View {
    let damus_state: DamusState
    
    @StateObject var following: FollowingModel
    
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(following.contacts, id: \.self) { pk in
                    FollowUserView(target: .pubkey(pk), damus_state: damus_state)
                }
            }
        }
        .onAppear {
            following.subscribe()
        }
        .onDisappear {
            following.unsubscribe()
        }
    }
}

/*
struct FollowingView_Previews: PreviewProvider {
    static var previews: some View {
        FollowingView(contact: <#NostrEvent#>, damus_state: <#DamusState#>)
    }
}
 */
