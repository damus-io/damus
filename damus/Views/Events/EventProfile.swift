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
    case .subheadline:
        return PFP_SIZE * 0.5
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
    
    var disable_animation: Bool {
        damus_state.settings.disable_animation
    }
    
    var body: some View {
        HStack(alignment: .center) {
            VStack {
                NavigationLink(destination: ProfileView(damus_state: damus_state, pubkey: pubkey)) {
                    ProfilePicView(pubkey: pubkey, size: pfp_size, highlight: .none, profiles: damus_state.profiles, disable_animation: disable_animation)
                }
            }
            
            EventProfileName(pubkey: pubkey, profile: profile, damus: damus_state, size: size)
        }
    }
}

struct EventProfile_Previews: PreviewProvider {
    static var previews: some View {
        EventProfile(damus_state: test_damus_state(), pubkey: "pk", profile: nil, size: .normal)
    }
}
