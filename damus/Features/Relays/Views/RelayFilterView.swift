//
//  RelayFilterView.swift
//  damus
//
//  Created by Ben Weeks on 1/8/23.
//

import SwiftUI

/// A sheet that lets the user filter the current timeline by relay and,
/// for Universe, quickly adjust whether multiple notes per user are shown.
struct RelayFilterView: View {
    let state: DamusState
    let timeline: Timeline
    
    init(state: DamusState, timeline: Timeline) {
        self.state = state
        self.timeline = timeline
    }
    
    /// The relays currently configured for the user.
    var relays: [RelayPool.RelayDescriptor] {
        state.nostrNetwork.ourRelayDescriptors
    }
    
    /// Whether the current sheet is being shown for Universe/Search.
    var isUniverseTimeline: Bool {
        timeline == .search
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text(
                "Please choose relays from the list below to filter the current feed:",
                comment: "Instructions on how to filter a specific timeline feed by choosing relay servers to filter on."
            )
            .padding()
            .padding(.top, 20)
            .padding(.bottom, 0)
            
            List {
                if isUniverseTimeline {
                    Section(
                        header: Text(
                            "Display",
                            comment: "Section header for universe display options in the relay filter sheet."
                        )
                    ) {
                        Toggle(
                            NSLocalizedString(
                                "View multiple events per user",
                                comment: "Setting to only see 1 event per user (npub) in the search/universe"
                            ),
                            isOn: Binding(
                                get: { state.settings.multiple_events_per_pubkey },
                                set: { state.settings.multiple_events_per_pubkey = $0 }
                            )
                        )
                        .toggleStyle(.switch)
                    }
                }
                
                Section(
                    header: Text(
                        "Relays",
                        comment: "Section header for relay toggles in the relay filter sheet."
                    )
                ) {
                    ForEach(Array(relays), id: \.url.id) { relay in
                        RelayToggle(state: state, timeline: timeline, relay_id: relay.url)
                    }
                }
            }
        }
    }
}

struct RelayFilterView_Previews: PreviewProvider {
    static var previews: some View {
        RelayFilterView(state: test_damus_state, timeline: .search)
    }
}