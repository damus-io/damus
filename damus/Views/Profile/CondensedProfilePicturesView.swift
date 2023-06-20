//
//  CondensedProfilePicturesView.swift
//  damus
//
//  Created by Terry Yiu on 6/19/23.
//

import SwiftUI

struct CondensedProfilePicturesView: View {
    let state: DamusState
    let pubkeys: [String]
    let maxPictures: Int

    init(state: DamusState, pubkeys: [String], maxPictures: Int) {
        self.state = state
        self.pubkeys = pubkeys
        self.maxPictures = min(maxPictures, pubkeys.count)
    }

    var body: some View {
        // Using ZStack to make profile pictures floating and stacked on top of each other.
        ZStack {
            ForEach((0..<maxPictures).reversed(), id: \.self) { index in
                ProfilePicView(pubkey: pubkeys[index], size: 32.0, highlight: .none, profiles: state.profiles, disable_animation: state.settings.disable_animation)
                    .offset(x: CGFloat(index) * 20)
            }
        }
        // Padding is needed so that other components drawn adjacent to this view don't get drawn on top.
        .padding(.trailing, CGFloat((maxPictures - 1) * 20))
    }
}

struct CondensedProfilePicturesView_Previews: PreviewProvider {
    static var previews: some View {
        CondensedProfilePicturesView(state: test_damus_state(), pubkeys: ["a", "b", "c", "d"], maxPictures: 3)
    }
}
