//
//  ProfilePicturesView.swift
//  damus
//
//  Created by William Casarin on 2023-02-22.
//

import SwiftUI

struct ProfilePicturesView: View {
    let state: DamusState
    let events: [NostrEvent]

    @State var nav_target: String? = nil
    @State var navigating: Bool = false
    
    var body: some View {
        NavigationLink(destination: ProfileView(damus_state: state, pubkey: nav_target ?? ""), isActive: $navigating) {
            EmptyView()
        }
        HStack {
            ForEach(events.prefix(8)) { ev in
                ProfilePicView(pubkey: ev.pubkey, size: 32.0, highlight: .none, profiles: state.profiles)
                    .onTapGesture {
                        nav_target = ev.pubkey
                        navigating = true
                    }
            }
        }
    }
}

struct ProfilePicturesView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicturesView(state: test_damus_state(), events: [test_event, test_event])
    }
}
