//
//  ReactionView.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import SwiftUI
import Kingfisher

struct ReactionView: View {
    let damus_state: DamusState
    let reaction: NostrEvent

    var content: String {
        return to_reaction_emoji(ev: reaction) ?? ""
    }

    /// The first custom emoji from the reaction event's tags, if present
    private var customEmoji: CustomEmoji? {
        reaction.referenced_custom_emojis.first
    }

    var body: some View {
        HStack {
            reactionContent
                .frame(width: 50, height: 50)

            FollowUserView(target: .pubkey(reaction.pubkey), damus_state: damus_state)
        }
    }

    @ViewBuilder
    private var reactionContent: some View {
        if let emoji = customEmoji {
            // Custom emoji reaction - load image dynamically
            KFAnimatedImage(emoji.url)
                .configure { view in view.framePreloadCount = 1 }
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
        } else {
            // Standard emoji reaction
            Text(content)
                .font(Font.headline)
        }
    }
}

struct ReactionView_Previews: PreviewProvider {
    static var previews: some View {
        ReactionView(damus_state: test_damus_state, reaction: NostrEvent(content: "🤙🏼", keypair: test_keypair)!)
    }
}
