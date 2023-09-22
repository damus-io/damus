//
//  ProfilePicturesView.swift
//  damus
//
//  Created by William Casarin on 2023-02-22.
//

import SwiftUI

struct ProfilePicturesView: View {
    let state: DamusState
    let pubkeys: [Pubkey]

    var body: some View {
        HStack {
            ForEach(pubkeys.prefix(8), id: \.self) { pubkey in
                ProfilePicView(pubkey: pubkey, size: 32.0, highlight: .none, profiles: state.profiles, disable_animation: state.settings.disable_animation)
                    .onTapGesture {
                        state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                    }
            }
        }
    }
}

struct ProfilePicturesView_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = test_note.pubkey
        ProfilePicturesView(state: test_damus_state, pubkeys: [pubkey, pubkey])
    }
}
