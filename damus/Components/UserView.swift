//
//  UserView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

struct UserView: View {
    let damus_state: DamusState
    let pubkey: String
    
    var body: some View {
        NavigationLink(destination: ProfileView(damus_state: damus_state, pubkey: pubkey)) {
            ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles)
        
            VStack(alignment: .leading) {
                let profile = damus_state.profiles.lookup(id: pubkey)
                ProfileName(pubkey: pubkey, profile: profile, damus: damus_state, show_friend_confirmed: false, show_nip5_domain: false)
                if let about = profile?.about {
                    Text(about)
                        .lineLimit(3)
                        .font(.footnote)
                }
            }
            
            Spacer()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct UserView_Previews: PreviewProvider {
    static var previews: some View {
        UserView(damus_state: test_damus_state(), pubkey: "pk")
    }
}
