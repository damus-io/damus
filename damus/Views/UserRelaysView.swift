//
//  UserRelaysView.swift
//  damus
//
//  Created by William Casarin on 2022-12-29.
//

import SwiftUI

struct UserRelaysView: View {
    let state: DamusState
    let pubkey: String
    let relays: [String]
    
    @State var relay_state: [(String, Bool)]
    @State private var showAddButton = false
    
    init (state: DamusState, pubkey: String, relays: [String]) {
        self.state = state
        self.pubkey = pubkey
        self.relays = relays
        let relay_state = UserRelaysView.make_relay_state(pool: state.pool, relays: relays)
        self._relay_state = State(initialValue: relay_state)
    }
    
    static func make_relay_state(pool: RelayPool, relays: [String]) -> [(String, Bool)] {
        return relays.map({ r in
            return (r, pool.get_relay(r) == nil)
        }).sorted { (a, b) in a.0 < b.0 }
    }
    
    var body: some View {
        List(relay_state, id: \.0) { (r, add) in
            RecommendedRelayView(damus: state, relay: r, add_button: add, showActionButtons: $showAddButton)
        }
        .onReceive(handle_notify(.relays_changed)) { _ in
            self.relay_state = UserRelaysView.make_relay_state(pool: state.pool, relays: self.relays)
        }
        .navigationBarTitle(NSLocalizedString("Relays", comment: "Navigation bar title that shows the list of relays for a user."))
        .toolbar{
            if state.keypair.privkey != nil {
                if showAddButton {
                    Button(NSLocalizedString("Done", comment: "Button that, when tapped, will finish adding a different user's relays to your relay by hiding the + buttons next to the relays.")) {
                        showAddButton.toggle()
                    }
                } else {
                    Button(NSLocalizedString("Show +", comment: "Button that, when tapped, will show + buttons next to a user's relays.")) {
                        showAddButton.toggle()
                    }
                }
            }
        }
    }
}

struct UserRelaysView_Previews: PreviewProvider {
    static var previews: some View {
        UserRelaysView(state: test_damus_state(), pubkey: "", relays: [])
    }
}
