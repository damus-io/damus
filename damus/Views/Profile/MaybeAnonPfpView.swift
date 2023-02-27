//
//  MaybeAnonPfpView.swift
//  damus
//
//  Created by William Casarin on 2023-02-26.
//

import SwiftUI

struct MaybeAnonPfpView: View {
    let state: DamusState
    let is_anon: Bool
    let pubkey: String
    
    init(state: DamusState, event: NostrEvent, pubkey: String) {
        self.state = state
        self.is_anon = event_is_anonymous(ev: event)
        self.pubkey = pubkey
    }
    
    init(state: DamusState, is_anon: Bool, pubkey: String) {
        self.state = state
        self.is_anon = is_anon
        self.pubkey = pubkey
    }
    
    var body: some View {
        Group {
            if is_anon {
                Image(systemName: "person.fill.questionmark")
                    .font(.largeTitle)
                    .frame(width: PFP_SIZE, height: PFP_SIZE)
            } else {
                NavigationLink(destination: ProfileView(damus_state: state, pubkey: pubkey)) {
                    ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: .none, profiles: state.profiles)
                }
            }
        }
    }
}

struct MaybeAnonPfpView_Previews: PreviewProvider {
    static var previews: some View {
        MaybeAnonPfpView(state: test_damus_state(), is_anon: true, pubkey: "anon")
    }
}
