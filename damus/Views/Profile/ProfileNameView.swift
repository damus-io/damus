//
//  ProfileNameView.swift
//  damus
//
//  Created by William Casarin on 2023-02-07.
//

import SwiftUI

struct ProfileNameView: View {
    let pubkey: String
    let profile: Profile?
    let follows_you: Bool
    let damus: DamusState
    
    var spacing: CGFloat { 10.0 }
    
    var body: some View {
        Group {
            if let real_name = profile?.display_name {
                VStack(alignment: .leading) {
                    Text(real_name)
                        .font(.title3.weight(.bold))
                    HStack(alignment: .center, spacing: spacing) {
                        ProfileName(pubkey: pubkey, profile: profile, prefix: "@", damus: damus, show_friend_confirmed: true)
                            .font(.callout)
                            .foregroundColor(.gray)
                        
                        if follows_you {
                            FollowsYou()
                        }
                    }
                    KeyView(pubkey: pubkey)
                        .pubkey_context_menu(bech32_pubkey: pubkey)
                }
            } else {
                VStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: spacing) {
                        ProfileName(pubkey: pubkey, profile: profile, damus: damus, show_friend_confirmed: true)
                            .font(.title3.weight(.bold))
                        if follows_you {
                            FollowsYou()
                        }
                    }
                    KeyView(pubkey: pubkey)
                        .pubkey_context_menu(bech32_pubkey: pubkey)
                }
            }
        }
    }
}

struct ProfileNameView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ProfileNameView(pubkey: test_event.pubkey, profile: nil, follows_you: true, damus: test_damus_state())
            
            ProfileNameView(pubkey: test_event.pubkey, profile: nil, follows_you: false, damus: test_damus_state())
        }
    }
}
