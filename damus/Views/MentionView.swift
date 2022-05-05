//
//  MentionView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI

struct MentionView: View {
    let mention: Mention
    
    @EnvironmentObject var profiles: Profiles
    
    var body: some View {
        switch mention.type {
        case .pubkey:
            PubkeyView(pubkey: mention.ref.ref_id, relay: mention.ref.relay_id)
                .environmentObject(profiles)
        case .event:
            Text("< e >")
            //EventBlockView(pubkey: mention.ref.ref_id, relay: mention.ref.relay_id)
        }
    }
}

/*
struct MentionView_Previews: PreviewProvider {
    static var previews: some View {
        MentionView()
    }
}
*/
