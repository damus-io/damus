//
//  LiveStreamHomeView.swift
//  damus
//
//  Created by eric on 7/25/25.
//

import SwiftUI
import CryptoKit
import NaturalLanguage

struct LiveStreamHomeView: View {
    let damus_state: DamusState
    @StateObject var model: LiveEventModel
    @Environment(\.colorScheme) var colorScheme

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)
        return ContentFilters(filters: filters).filter
    }
    
    var body: some View {
        VStack {
            LiveStreamTimelineView<AnyView>(events: model.events, loading: $model.loading, damus: damus_state, filter:content_filter(FilterState.live))
        }
        .padding(.bottom)
        .refreshable {
            // Fetch new information by unsubscribing and resubscribing to the relay
            model.unsubscribe()
            model.subscribe()
        }
        .onReceive(handle_notify(.new_mutes)) { _ in
            self.model.filter_muted()
        }
        .onAppear {
            model.subscribe()
        }
        .onDisappear {
            model.unsubscribe()
        }
    }
}

struct LiveStreamHomeView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        LiveStreamHomeView(damus_state: state, model: LiveEventModel(damus_state: state))
    }
}
