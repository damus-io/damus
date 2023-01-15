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
                Text("\(bar.boosts)")
                    .font(.body.bold())
                Text("Repost".conformPlurality(count: bar.boosts))
                    .foregroundColor(.gray)
            }

            if bar.likes > 0 {
                NavigationLink(destination: ReactionsView(damus_state: state, model: ReactionsModel(state: state, target: target))) {
                    Text("\(bar.likes)")
                        .font(.body.bold())
                    Text("Reaction".conformPlurality(count: bar.likes))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if bar.tips > 0 {
                Text("\(bar.tips)")
                    .font(.body.bold())
                Text("Tip".conformPlurality(count: bar.tips))
                    .foregroundColor(.gray)
            }
        }
    }
}

struct EventDetailBar_Previews: PreviewProvider {
    static var previews: some View {
        EventDetailBar(state: test_damus_state(), target: "", bar: ActionBarModel.empty())
    }
}
