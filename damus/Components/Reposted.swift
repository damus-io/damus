//
//  Reposted.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import SwiftUI

struct Reposted: View {
    let damus: DamusState
    let pubkey: Pubkey
    let target: NoteId

    var body: some View {
        HStack(alignment: .center) {
            Image("repost")
                .foregroundColor(Color.gray)
            ProfileName(pubkey: pubkey, damus: damus, show_nip5_domain: false)
                    .foregroundColor(Color.gray)
            let other_reposts = (damus.boosts.counts[target] ?? 0) - 1
            if other_reposts > 0 {
                Text(" and \(other_reposts) others reposted", comment: "Text indicating that the note was reposted (i.e. re-shared) by multiple people")
                    .foregroundColor(Color.gray)
            } else {
                Text("reposted", comment: "Text indicating that the note was reposted (i.e. re-shared).")
                    .foregroundColor(Color.gray)
            }
        }
    }
}

struct Reposted_Previews: PreviewProvider {
    static var previews: some View {
        let test_state = test_damus_state
        Reposted(damus: test_state, pubkey: test_state.pubkey, target: test_note.id)
    }
}
