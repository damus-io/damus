//
//  EventProfile.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

func eventview_pfp_size(_ size: EventViewKind) -> CGFloat {
    switch size {
    case .small:
        return PFP_SIZE * 0.5
    case .normal:
        return PFP_SIZE
    case .selected:
        return PFP_SIZE
    }
}

struct EventProfile: View {
    let damus_state: DamusState
    let pubkey: String
    let profile: Profile?
    let size: EventViewKind
    
    var pfp_size: CGFloat {
        eventview_pfp_size(size)
    }
    
    var body: some View {
        HStack(alignment: .center) {
            VStack {
                let pmodel = ProfileModel(pubkey: pubkey, damus: damus_state)
                let pv = ProfileView(damus_state: damus_state, profile: pmodel, followers: FollowersModel(damus_state: damus_state, target: pubkey))
                
                NavigationLink(destination: pv) {
                    ProfilePicView(pubkey: pubkey, size: pfp_size, highlight: .none, profiles: damus_state.profiles, contacts: damus_state.contacts)
                }
            }
            
            EventProfileName(pubkey: pubkey, profile: profile, damus: damus_state, show_friend_confirmed: true, size: size)
        }
    }
}

struct EventProfile_Previews: PreviewProvider {
    static var previews: some View {
        EventProfile(damus_state: test_damus_state(), pubkey: "pk", profile: nil, size: .normal)
    }
}
