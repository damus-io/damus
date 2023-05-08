//
//  ProfilePicturesView.swift
//  damus
//
//  Created by William Casarin on 2023-02-22.
//

import SwiftUI

struct ProfilePicturesView: View {
    let state: DamusState
    let pubkeys: [String]

    @State var nav_target: String? = nil
    @State var navigating: Bool = false
    
    var body: some View {
        NavigationLink(destination: ProfileView(damus_state: state, pubkey: nav_target ?? ""), isActive: $navigating) {
            EmptyView()
        }
        HStack {
            ForEach(pubkeys.prefix(8), id: \.self) { pubkey in
                ProfilePicView(pubkey: pubkey, size: 32.0, highlight: .none, profiles: state.profiles, disable_animation: state.settings.disable_animation)
                    .onTapGesture {
                        nav_target = pubkey
                        navigating = true
                    }
            }
        }
    }
}

struct ProfilePicturesView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicturesView(state: test_damus_state(), pubkeys: ["a", "b"])
    }
}
