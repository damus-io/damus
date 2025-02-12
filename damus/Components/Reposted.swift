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
    @State var reposts: Int

    init(damus: DamusState, pubkey: Pubkey, target: NoteId) {
        self.damus = damus
        self.pubkey = pubkey
        self.target = target
        self.reposts = damus.boosts.counts[target] ?? 1
    }

    var body: some View {
        HStack(alignment: .center) {
            Image("repost")
                .foregroundColor(Color.gray)
            ProfileName(pubkey: pubkey, damus: damus, show_nip5_domain: false)
                    .foregroundColor(Color.gray)
            NavigationLink(value: Route.Reposts(reposts: .reposts(state: damus, target: target))) {
                let other_reposts = reposts - 1
                if other_reposts > 0 {
                        Text(" and \(other_reposts) others reposted", comment: "Text indicating that the note was reposted (i.e. re-shared) by multiple people")
                            .foregroundColor(Color.gray)
                } else {
                    Text("reposted", comment: "Text indicating that the note was reposted (i.e. re-shared).")
                        .foregroundColor(Color.gray)
                }
            }
        }
        .onReceive(handle_notify(.update_stats), perform: { note_id in
            guard note_id == target else { return }
            let repost_count = damus.boosts.counts[target]
            if let repost_count, reposts != repost_count {
                reposts = repost_count
            }
        })
    }
}

struct Reposted_Previews: PreviewProvider {
    static var previews: some View {
        let test_state = test_damus_state
        Reposted(damus: test_state, pubkey: test_state.pubkey, target: test_note.id)
    }
}
