//
//  RepostView.swift
//  damus
//
//  Created by Terry Yiu on 1/22/23.
//

import SwiftUI

struct RepostView: View {
    let damus_state: DamusState
    let repost: NostrEvent

    var body: some View {
        FollowUserView(target: .pubkey(repost.pubkey), damus_state: damus_state)
    }
}

struct RepostView_Previews: PreviewProvider {
    static var previews: some View {
        RepostView(damus_state: test_damus_state(), repost: NostrEvent(id: "", content: "", pubkey: ""))
    }
}

