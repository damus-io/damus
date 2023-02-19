//
//  ReactionsView.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import SwiftUI

struct ReactionsView: View {
    let damus_state: DamusState
    @StateObject var model: ReactionsModel
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(model.events, id: \.id) { ev in
                    ReactionView(damus_state: damus_state, reaction: ev)
                }
            }
            .padding()
        }
        .navigationBarTitle(NSLocalizedString("Reactions", comment: "Navigation bar title for Reactions view."))
        .onAppear {
            model.subscribe()
        }
        .onDisappear {
            model.unsubscribe()
        }
    }
}

struct ReactionsView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state()
        ReactionsView(damus_state: state, model: ReactionsModel(state: state, target: "pubkey"))
    }
}
