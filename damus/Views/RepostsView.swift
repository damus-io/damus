//
//  RepostsView.swift
//  damus
//
//  Created by Terry Yiu on 1/22/23.
//

import SwiftUI

struct RepostsView: View {
    let damus_state: DamusState
    @StateObject var model: EventsModel

    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(model.events.events, id: \.id) { ev in
                    RepostView(damus_state: damus_state, repost: ev)
                }
            }
            .padding()
        }
        .padding(.bottom, tabHeight)
        .navigationBarTitle(NSLocalizedString("Reposts", comment: "Navigation bar title for Reposts view."))
        .onAppear {
            model.subscribe()
        }
        .onDisappear {
            model.unsubscribe()
        }
    }
}

struct RepostsView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        RepostsView(damus_state: state, model: .reposts(state: state, target: test_note.id))
    }
}
