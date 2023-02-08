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
    
    func toggle_binding(relay_id: String) -> Binding<Bool> {
        return Binding(get: {
            !state.relay_filters.is_filtered(timeline: timeline, relay_id: relay_id)
        }, set: { on in
            if !on {
                state.relay_filters.insert(timeline: timeline, relay_id: relay_id)
            } else {
                state.relay_filters.remove(timeline: timeline, relay_id: relay_id)
            }
        })
    }
    
    var body: some View {
        Text("To filter your \(timeline.rawValue) feed, please choose applicable relays from the list below:")
            .padding()
            .padding(.top, 20)
            .padding(.bottom, 0)
        
        List(Array(relays), id: \.url) { relay in
            //RelayView(state: state, relay: relay.url.absoluteString)
            let relay_id = relay.url.absoluteString
            Toggle(relay_id, isOn: toggle_binding(relay_id: relay_id))
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
    }
}

struct RelayFilterView_Previews: PreviewProvider {
    static var previews: some View {
        RelayFilterView(state: test_damus_state(), timeline: .search)
    }
}
