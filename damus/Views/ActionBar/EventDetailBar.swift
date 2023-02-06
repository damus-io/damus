//
//  EventDetailBar.swift
//  damus
//
//  Created by William Casarin on 2023-01-08.
//

import SwiftUI

struct EventDetailBar: View {
    let state: DamusState
    let target: String
    @StateObject var bar: ActionBarModel
    
    var body: some View {
        HStack {
            if bar.boosts > 0 {
                NavigationLink(destination: RepostsView(damus_state: state, model: RepostsModel(state: state, target: target))) {
                    Text("\(Text("\(bar.boosts)", comment: "Number of reposts.").font(.body.bold())) \(Text(String(format: NSLocalizedString("reposts_count", comment: "Part of a larger sentence to describe how many reposts there are."), bar.boosts)).foregroundColor(.gray))", comment: "Sentence composed of 2 variables to describe how many reposts. In source English, the first variable is the number of reposts, and the second variable is 'Repost' or 'Reposts'.")
                }
                .buttonStyle(PlainButtonStyle())
            }

            if bar.likes > 0 {
                NavigationLink(destination: ReactionsView(damus_state: state, model: ReactionsModel(state: state, target: target))) {
                    Text("\(Text("\(bar.likes)", comment: "Number of reactions on a post.").font(.body.bold())) \(Text(String(format: NSLocalizedString("reactions_count", comment: "Part of a larger sentence to describe how many reactions there are on a post."), bar.likes)).foregroundColor(.gray))", comment: "Sentence composed of 2 variables to describe how many reactions there are on a post. In source English, the first variable is the number of reactions, and the second variable is 'Reaction' or 'Reactions'.")
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if bar.zaps > 0 {
                Text("\(Text("\(bar.zaps)", comment: "Number of zap payments on a post.").font(.body.bold())) \(Text(String(format: NSLocalizedString("zaps_count", comment: "Part of a larger sentence to describe how many zap payments there are on a post."), bar.boosts)).foregroundColor(.gray))", comment: "Sentence composed of 2 variables to describe how many zap payments there are on a post. In source English, the first variable is the number of zap payments, and the second variable is 'Zap' or 'Zaps'.")
            }
        }
    }
}

struct EventDetailBar_Previews: PreviewProvider {
    static var previews: some View {
        EventDetailBar(state: test_damus_state(), target: "", bar: ActionBarModel.empty())
    }
}
