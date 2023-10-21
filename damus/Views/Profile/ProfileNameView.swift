//
//  ProfileNameView.swift
//  damus
//
//  Created by William Casarin on 2023-02-07.
//

import SwiftUI

struct ProfileNameView: View {
    let pubkey: Pubkey
    let damus: DamusState
    
    var spacing: CGFloat { 10.0 }
    
    var body: some View {
        Group {
            VStack(alignment: .leading) {
                let profile_txn = self.damus.profiles.lookup(id: pubkey)
                let profile = profile_txn.unsafeUnownedValue

                switch Profile.displayName(profile: profile, pubkey: pubkey) {
                case .one:
                    HStack(alignment: .center, spacing: spacing) {
                        ProfileName(pubkey: pubkey, damus: damus)
                            .font(.title3.weight(.bold))
                    }
                case .both(username: _, displayName: let displayName):
                    Text(displayName)
                        .font(.title3.weight(.bold))
                    
                    HStack(alignment: .center, spacing: spacing) {
                        ProfileName(pubkey: pubkey, prefix: "@", damus: damus)
                            .font(.callout)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                PubkeyView(pubkey: pubkey)
                    .pubkey_context_menu(pubkey: pubkey)
            }
        }
    }
}

struct ProfileNameView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ProfileNameView(pubkey: test_note.pubkey, damus: test_damus_state)

            ProfileNameView(pubkey: test_note.pubkey, damus: test_damus_state)
        }
    }
}
