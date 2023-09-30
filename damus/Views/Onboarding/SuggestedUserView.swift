//
//  SuggestedUserView.swift
//  damus
//
//  Created by klabo on 7/18/23.
//

import SwiftUI

struct SuggestedUser {
    let pubkey: Pubkey
    let name: String
    let about: String
    let pfp: URL

    init?(name: String?, about: String?, picture: String?, pubkey: Pubkey) {
        guard let name, let about, let picture,
              let pfpURL = URL(string: picture) else {
            return nil
        }

        self.pubkey = pubkey
        self.name = name
        self.about = about
        self.pfp = pfpURL
    }
}

struct SuggestedUserView: View {
    let user: SuggestedUser
    let damus_state: DamusState

    var body: some View {
        HStack {
            let target = FollowTarget.pubkey(user.pubkey)
            InnerProfilePicView(url: user.pfp,
                                fallbackUrl: nil,
                                pubkey: target.pubkey,
                                size: 50,
                                highlight: .none,
                                disable_animation: false)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ProfileName(pubkey: user.pubkey, damus: damus_state)
                }
                Text(user.about)
                    .lineLimit(3)
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            Spacer()
            GradientFollowButton(target: target, follows_you: false, follow_state: damus_state.contacts.follow_state(target.pubkey))
        }
    }
}

struct SuggestedUserView_Previews: PreviewProvider {
    static var previews: some View {
        let pfp = "https://primal.b-cdn.net/media-cache?s=m&a=1&u=https%3A%2F%2Fpbs.twimg.com%2Fprofile_images%2F1599994711430742017%2F33zLk9Wi_400x400.jpg"
        let profile = Profile(name: "klabo", about: "A person who likes nostr a lot and I like to tell people about myself in very long-winded ways that push the limits of UI and almost break things", picture: pfp)

        let user = SuggestedUser(name: "klabo", about: "name", picture: "about", pubkey: test_pubkey)!
        List {
            SuggestedUserView(user: user, damus_state: test_damus_state)
        }
    }
}
