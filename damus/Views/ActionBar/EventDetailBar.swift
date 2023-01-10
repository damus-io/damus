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
            Text("\(bar.boosts)")
                .font(.body.bold())
            Text("Reposts")

            NavigationLink(destination: ReactionsView(damus_state: state, model: ReactionsModel(state: state, target: target))) {
                Text("\(bar.likes)")
                    .font(.body.bold())
                Text("Reactions")
            }
            .buttonStyle(PlainButtonStyle())
            
            Text("\(bar.tips)")
                .font(.body.bold())
            Text("Tips")
        }
    }
}

struct EventDetailBar_Previews: PreviewProvider {
    static var previews: some View {
        EventDetailBar(state: test_damus_state(), target: "", bar: ActionBarModel.empty())
    }
}
