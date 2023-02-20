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
    //@State var relays: [RelayDescriptor]
    //@EnvironmentObject var user_settings: UserSettingsStore
    //@State var relays: [RelayDescriptor]
    
    init(state: DamusState, timeline: Timeline) {
        self.state = state
        self.timeline = timeline
        
        //_relays = State(initialValue: state.pool.descriptors)
    }
    
    var relays: [RelayDescriptor] {
        return state.pool.descriptors
    }
    
    var body: some View {
        Text("To filter your \(timeline.rawValue) feed, please choose applicable relays from the list below:", comment: "Instructions on how to filter a specific timeline feed by choosing relay servers to filter on.")
            .padding()
            .padding(.top, 20)
            .padding(.bottom, 0)
        
        List(Array(relays), id: \.url) { relay in
            RelayToggle(state: state, timeline: timeline, relay_id: relay.url.absoluteString)
        }
    }
}

struct RelayFilterView_Previews: PreviewProvider {
    static var previews: some View {
        RelayFilterView(state: test_damus_state(), timeline: .search)
    }
}
