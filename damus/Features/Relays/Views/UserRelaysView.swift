//
//  UserRelaysView.swift
//  damus
//
//  Created by William Casarin on 2022-12-29.
//

import SwiftUI

struct UserRelaysView: View {
    let state: DamusState
    let relays: [RelayURL]

    @State var relay_state: [(RelayURL, Bool)]

    init(state: DamusState, relays: [RelayURL]) {
        self.state = state
        self.relays = relays
        let relay_state = UserRelaysView.make_relay_state(state: state, relays: relays)
        self._relay_state = State(initialValue: relay_state)
    }

    static func make_relay_state(state: DamusState, relays: [RelayURL]) -> [(RelayURL, Bool)] {
        return relays.map({ r in
            return (r, state.nostrNetwork.getRelay(r) == nil)
        }).sorted { (a, b) in a.0 < b.0 }
    }
    
    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { state.settings.enable_vine_relay },
                    set: { setDivineRelayEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Divine Relay", comment: "Label for the relay that powers Vine videos.")
                            .font(.headline)
                        Text("Required for Vine videos and divine.video content.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Relays", comment: "Header for the list of relays a user connects to.")) {
                ForEach(relay_state, id: \.0) { (r, add) in
                    RelayView(state: state, relay: r, showActionButtons: .constant(true), recommended: true)
                }
            }
        }
        .listStyle(PlainListStyle())
        .navigationBarTitle(NSLocalizedString("Relays", comment: "Navigation bar title that shows the list of relays for a user."))
    }
    
    private func setDivineRelayEnabled(_ enabled: Bool) {
        state.settings.enable_vine_relay = enabled
        Task {
            if enabled {
                await state.nostrNetwork.ensureRelayConnected(.vineRelay)
            } else {
                await state.nostrNetwork.disconnectRelay(.vineRelay)
            }
        }
    }
}

struct UserRelaysView_Previews: PreviewProvider {
    static var previews: some View {
        UserRelaysView(state: test_damus_state, relays: [])
    }
}
