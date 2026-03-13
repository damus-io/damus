//
//  CondensedProfilePicturesView.swift
//  damus
//
//  Created by Terry Yiu on 6/19/23.
//

import SwiftUI

/// Displays multiple profile pictures in a horizontally overlapping stack.
/// Used to show a condensed view of multiple users (e.g., "Notes from X, Y, Z").
struct CondensedProfilePicturesView: View {
    let model: CondensedProfilePicturesViewModel

    /// The diameter of each profile picture in points.
    /// Defaults to 32pt for standard usage; can be reduced for compact layouts.
    let size: CGFloat

    init(state: DamusState, pubkeys: [Pubkey], maxPictures: Int, size: CGFloat = 32.0) {
        self.model = CondensedProfilePicturesViewModel(state: state, pubkeys: pubkeys, maxPictures: maxPictures)
        self.size = size
    }

    /// Horizontal offset between stacked pictures, proportional to size.
    /// At 32pt size, offset is 20pt (~62.5% of diameter) for readable overlap.
    private var pictureOffset: CGFloat {
        size * 0.625
    }

    var body: some View {
        // ZStack renders pictures back-to-front so the first pubkey appears on top.
        // We reverse the loop so index 0 is drawn last (on top).
        ZStack {
            ForEach((0..<model.maxPictures).reversed(), id: \.self) { index in
                ProfilePicView(
                    pubkey: model.pubkeys[index],
                    size: size,
                    highlight: .none,
                    profiles: model.state.profiles,
                    disable_animation: model.state.settings.disable_animation,
                    damusState: model.state
                )
                .offset(x: CGFloat(index) * pictureOffset)
            }
        }
        // Trailing padding reserves space for the stacked pictures so adjacent
        // views don't overlap. Total width = size + (maxPictures - 1) * offset.
        .padding(.trailing, CGFloat(model.maxPictures - 1) * pictureOffset)
    }
}

struct CondensedProfilePicturesView_Previews: PreviewProvider {
    static var previews: some View {
        CondensedProfilePicturesView(state: test_damus_state, pubkeys: [test_pubkey, test_pubkey, test_pubkey, test_pubkey], maxPictures: 3)
    }
}
