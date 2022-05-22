//
//  FollowingView.swift
//  damus
//
//  Created by William Casarin on 2022-05-16.
//

import SwiftUI

struct FollowUserView: View {
    let pubkey: String
    let damus_state: DamusState
    
    var body: some View {
        HStack(alignment: .top) {
            let pmodel = ProfileModel(pubkey: pubkey, damus: damus_state)
            let pv = ProfileView(damus_state: damus_state, profile: pmodel)
            
            NavigationLink(destination: pv) {
                ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: .none, image_cache: damus_state.image_cache, profiles: damus_state.profiles)
            }
            
            VStack(alignment: .leading) {
                let profile = damus_state.profiles.lookup(id: pubkey)
                ProfileName(pubkey: pubkey, profile: profile)
                if let about = profile.flatMap { $0.about } {
                    Text(about)
                }
            }
            
            Spacer()
            
            FollowButtonView(pubkey: pubkey, follow_state: damus_state.contacts.follow_state(pubkey))
        }
    }
}

struct FollowingView: View {
    let contact: NostrEvent
    let damus_state: DamusState
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(contact.referenced_pubkeys) { pk in
                    FollowUserView(pubkey: pk.ref_id, damus_state: damus_state)
                }
            }
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
