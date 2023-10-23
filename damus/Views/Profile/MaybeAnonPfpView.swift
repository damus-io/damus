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
    let pubkey: Pubkey
    let size: CGFloat
    
    init(state: DamusState, is_anon: Bool, pubkey: Pubkey, size: CGFloat) {
        self.state = state
        self.is_anon = is_anon
        self.pubkey = pubkey
        self.size = size
    }
    
    var body: some View {
        ZStack {
            if is_anon {
                Image("question")
                    .resizable()
                    .font(.largeTitle)
                    .frame(width: size, height: size)
            } else {
                ProfilePicView(pubkey: pubkey, size: size, highlight: .none, profiles: state.profiles, disable_animation: state.settings.disable_animation, show_zappability: true)
                    .onTapGesture {
                        show_profile_action_sheet_if_enabled(damus_state: state, pubkey: pubkey)
                    }
            }
        }
    }
}

struct MaybeAnonPfpView_Previews: PreviewProvider {
    static var previews: some View {
        MaybeAnonPfpView(state: test_damus_state, is_anon: true, pubkey: ANON_PUBKEY, size: PFP_SIZE)
    }
}
