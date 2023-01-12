//
//  Reposted.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import SwiftUI

struct Reposted: View {
    let damus: DamusState
    let pubkey: String
    let profile: Profile?
    
    var body: some View {
        HStack(alignment: .center) {
            Image(systemName: "arrow.2.squarepath")
                .font(.footnote)
                .foregroundColor(Color.gray)
            ProfileName(pubkey: pubkey, profile: profile, damus: damus, show_friend_confirmed: true, show_nip5_domain: false)
                    .foregroundColor(Color.gray)
            Text("Reposted", comment: "Text indicating that the post was reposted (i.e. re-shared).")
                .font(.footnote)
                .foregroundColor(Color.gray)
        }
    }
}

struct Reposted_Previews: PreviewProvider {
    static var previews: some View {
        let test_state = test_damus_state()
        Reposted(damus: test_state, pubkey: test_state.pubkey, profile: make_test_profile())
    }
}
