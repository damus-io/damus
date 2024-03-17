//
//  EventDetailBar.swift
//  damus
//
//  Created by William Casarin on 2023-01-08.
//

import SwiftUI

struct EventDetailBar: View {
    let state: DamusState
    let target: NoteId
    let target_pk: Pubkey

    @ObservedObject var bar: ActionBarModel
    
    init(state: DamusState, target: NoteId, target_pk: Pubkey) {
        self.state = state
        self.target = target
        self.target_pk = target_pk
        self._bar = ObservedObject(wrappedValue: make_actionbar_model(ev: target, damus: state))
        
    }
    
    var body: some View {
        HStack {
            if bar.boosts > 0 {
                NavigationLink(value: Route.Reposts(reposts: .reposts(state: state, target: target))) {
                    let nounString = pluralizedString(key: "reposts_count", count: bar.boosts)
                    let noun = Text(nounString).foregroundColor(.gray)
                    Text("\(Text(verbatim: bar.boosts.formatted()).font(.body.bold())) \(noun)", comment: "Sentence composed of 2 variables to describe how many reposts. In source English, the first variable is the number of reposts, and the second variable is 'Repost' or 'Reposts'.")
                }
                .buttonStyle(PlainButtonStyle())
            }

            if bar.quote_reposts > 0 {
                NavigationLink(value: Route.QuoteReposts(quotes: .quotes(state: state, target: target))) {
                    let nounString = pluralizedString(key: "quoted_reposts_count", count: bar.quote_reposts)
                    let noun = Text(nounString).foregroundColor(.gray)
                    Text("\(Text(verbatim: bar.quote_reposts.formatted()).font(.body.bold())) \(noun)", comment: "Sentence composed of 2 variables to describe how many quoted reposts. In source English, the first variable is the number of reposts, and the second variable is 'Repost' or 'Reposts'.")
                }
                .buttonStyle(PlainButtonStyle())
            }

            if bar.likes > 0 && !state.settings.onlyzaps_mode {
                NavigationLink(value: Route.Reactions(reactions: .likes(state: state, target: target))) {
                    let nounString = pluralizedString(key: "reactions_count", count: bar.likes)
                    let noun = Text(nounString).foregroundColor(.gray)
                    Text("\(Text(verbatim: bar.likes.formatted()).font(.body.bold())) \(noun)", comment: "Sentence composed of 2 variables to describe how many reactions there are on a post. In source English, the first variable is the number of reactions, and the second variable is 'Reaction' or 'Reactions'.")
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if bar.zaps > 0 {
                NavigationLink(value: Route.Zaps(target: .note(id: target, author: target_pk))) {
                    let nounString = pluralizedString(key: "zaps_count", count: bar.zaps)
                    let noun = Text(nounString).foregroundColor(.gray)
                    Text("\(Text(verbatim: bar.zaps.formatted()).font(.body.bold())) \(noun)", comment: "Sentence composed of 2 variables to describe how many zap payments there are on a post. In source English, the first variable is the number of zap payments, and the second variable is 'Zap' or 'Zaps'.")
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct EventDetailBar_Previews: PreviewProvider {
    static var previews: some View {
        EventDetailBar(state: test_damus_state, target: .empty, target_pk: .empty)
    }
}
