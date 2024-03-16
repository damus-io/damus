//
//  QuoteRepostsView.swift
//  damus
//
//  Created by William Casarin on 2024-03-16.
//

import SwiftUI

struct QuoteRepostsView: View {
    let damus_state: DamusState
    @ObservedObject var model: EventsModel

    var body: some View {
        TimelineView<AnyView>(events: model.events, loading: $model.loading, damus: damus_state, show_friend_icon: true, filter: ContentFilters.default_filters(damus_state: damus_state).filter(ev:))
        .navigationBarTitle(NSLocalizedString("Quotes", comment: "Navigation bar title for Quote Reposts view."))
        .onAppear {
            model.subscribe()
        }
        .onDisappear {
            model.unsubscribe()
        }
    }
}

struct QuoteRepostsView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        QuoteRepostsView(damus_state: state, model: .reposts(state: state, target: test_note.id))
    }
}
