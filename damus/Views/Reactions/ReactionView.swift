//
//  ReactionView.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import SwiftUI

struct ReactionView: View {
    let damus_state: DamusState
    let reaction: NostrEvent
    
    var content: String {
        return to_reaction_emoji(ev: reaction) ?? ""
    }
    
    var body: some View {
        HStack {
            Text(content)
                .font(Font.headline)
                .frame(width: 50, height: 50)
            
            FollowUserView(target: .pubkey(reaction.pubkey), damus_state: damus_state)
        }
    }
}

struct ReactionView_Previews: PreviewProvider {
    static var previews: some View {
        ReactionView(damus_state: test_damus_state(), reaction: NostrEvent(content: "🤙🏼", keypair: test_keypair)!)
    }
}
