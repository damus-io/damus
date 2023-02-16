//
//  RelayToggle.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

struct RelayToggle: View {
    let state: DamusState
    let timeline: Timeline
    let relay_id: String
    
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
        HStack {
            RelayStatus(pool: state.pool, relay: relay_id)
            RelayType(is_paid: state.relay_metadata.lookup(relay_id: relay_id)?.is_paid ?? false)
            Toggle(relay_id, isOn: toggle_binding(relay_id: relay_id))
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
    }
}

struct RelayToggle_Previews: PreviewProvider {
    static var previews: some View {
        RelayToggle(state: test_damus_state(), timeline: .search, relay_id: "wss://jb55.com")
            .padding()
    }
}
