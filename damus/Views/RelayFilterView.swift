//
//  RelayFilterView.swift
//  damus
//
//  Created by Ben Weeks on 1/8/23.
//

import SwiftUI

struct RelayFilterView: View {
    let state: DamusState
    let timeline: Timeline
    
    init(state: DamusState, timeline: Timeline) {
        self.state = state
        self.timeline = timeline
        
        //_relays = State(initialValue: state.networkManager.pool.descriptors)
    }
    
    var relays: [RelayPool.RelayDescriptor] {
        return state.nostrNetwork.pool.our_descriptors
    }
    
    var body: some View {
        Text("Please choose relays from the list below to filter the current feed:", comment: "Instructions on how to filter a specific timeline feed by choosing relay servers to filter on.")
            .padding()
            .padding(.top, 20)
            .padding(.bottom, 0)

        List(Array(relays), id: \.url.id) { relay in
            RelayToggle(state: state, timeline: timeline, relay_id: relay.url)
        }
    }
}

struct RelayFilterView_Previews: PreviewProvider {
    static var previews: some View {
        RelayFilterView(state: test_damus_state, timeline: .search)
    }
}
