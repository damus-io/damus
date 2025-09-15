//
//  CondensedProfilePicturesView.swift
//  damus
//
//  Created by Terry Yiu on 6/19/23.
//

import SwiftUI

struct CondensedProfilePicturesView: View {
    let model: CondensedProfilePicturesViewModel

    init(state: DamusState, pubkeys: [Pubkey], maxPictures: Int) {
        self.model = CondensedProfilePicturesViewModel(state: state, pubkeys: pubkeys, maxPictures: maxPictures)
    }

    var body: some View {
        // Using ZStack to make profile pictures floating and stacked on top of each other.
        ZStack {
            ForEach((0..<model.maxPictures).reversed(), id: \.self) { index in
                ProfilePicView(pubkey: model.pubkeys[index], size: 32.0, highlight: .none, profiles: model.state.profiles, disable_animation: model.state.settings.disable_animation)
                    .offset(x: CGFloat(index) * 20)
            }
        }
        // Padding is needed so that other components drawn adjacent to this view don't get drawn on top.
        .padding(.trailing, CGFloat((model.maxPictures - 1) * 20))
        .onAppear {
            self.model.load()
        }
        
    }
}

struct CondensedProfilePicturesView_Previews: PreviewProvider {
    static var previews: some View {
        CondensedProfilePicturesView(state: test_damus_state, pubkeys: [test_pubkey, test_pubkey, test_pubkey, test_pubkey], maxPictures: 3)
    }
}
