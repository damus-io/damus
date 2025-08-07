//
//  LiveStreamProfile.swift
//  damus
//
//  Created by eric on 8/8/25.
//

import SwiftUI

struct LiveStreamProfile: View {
    var state: DamusState
    var pubkey: Pubkey
    var size: CGFloat = 25
    
    var body: some View {
        HStack {
            ProfilePicView(pubkey: pubkey, size: size, highlight: .custom(DamusColors.neutral3, 1.0), profiles: state.profiles, disable_animation: state.settings.disable_animation, show_zappability: true)
                .onTapGesture {
                    state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                }
            let profile_txn = state.profiles.lookup(id: pubkey)
            let profile = profile_txn?.unsafeUnownedValue
            let displayName = Profile.displayName(profile: profile, pubkey: pubkey)
            switch displayName {
            case .one(let one):
                Text(one)
                    .font(.subheadline).foregroundColor(.gray)
                
            case .both(username: let username, displayName: let displayName):
                HStack(spacing: 6) {
                    Text(verbatim: displayName)
                        .font(.subheadline).foregroundColor(.gray)
                    
                    Text(verbatim: "@\(username)")
                        .font(.subheadline).foregroundColor(.gray)
                }
            }
        }
        .padding(5)
    }
    
}
