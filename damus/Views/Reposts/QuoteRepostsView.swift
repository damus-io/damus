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
        TimelineView(events: model.events, loading: $model.loading, damus: damus_state, show_friend_icon: true, filter: ContentFilters.default_filters(damus_state: damus_state).filter(ev:)) {
            ZStack(alignment: .leading) {
                DamusBackground(maxHeight: 250)
                    .mask(LinearGradient(gradient: Gradient(colors: [.black, .black, .black, .clear]), startPoint: .top, endPoint: .bottom))
                Text("Quotes", comment: "Navigation bar title for Quote Reposts view.")
                    .foregroundStyle(DamusLogoGradient.gradient)
                    .font(.title.bold())
                    .padding(.leading, 30)
                    .padding(.top, 30)
            }
        }
        .ignoresSafeArea()
        .padding(.bottom, tabHeight)
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
