//
//  UserView.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import SwiftUI

struct UserViewRow: View {
    let damus_state: DamusState
    let pubkey: Pubkey

    var body: some View {
        UserView(damus_state: damus_state, pubkey: pubkey)
            .contentShape(Rectangle())
            .background(.clear)
    }
}

struct UserView: View {
    let damus_state: DamusState
    let pubkey: Pubkey
    let spacer: Bool
    
    @State var about_text: Text? = nil
    
    init(damus_state: DamusState, pubkey: Pubkey, spacer: Bool = true) {
        self.damus_state = damus_state
        self.pubkey = pubkey
        self.spacer = spacer
    }
    
    var body: some View {
        VStack {
            HStack {
                ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
            
                VStack(alignment: .leading) {
                    ProfileName(pubkey: pubkey, damus: damus_state, show_nip5_domain: false)
                    if let about_text {
                        about_text
                            .lineLimit(3)
                            .font(.footnote)
                    }
                }
                
                if spacer {
                    Spacer()
                }
            }
        }
    }
}

struct UserView_Previews: PreviewProvider {
    static var previews: some View {
        UserView(damus_state: test_damus_state, pubkey: test_note.pubkey)
    }
}
