//
//  MentionView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI

struct MentionView: View {
    let mention: Mention
    let profiles: Profiles
    
    var body: some View {
        switch mention.type {
        case .pubkey:
            let pk = bech32_pubkey(mention.ref.ref_id) ?? mention.ref.ref_id
            PubkeyView(pubkey: pk, relay: mention.ref.relay_id)
        case .event:
            Text(String("< e >"))
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
