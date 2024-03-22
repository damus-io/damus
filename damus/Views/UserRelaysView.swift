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
        let relay_state = UserRelaysView.make_relay_state(pool: state.pool, relays: relays)
        self._relay_state = State(initialValue: relay_state)
    }

    static func make_relay_state(pool: RelayPool, relays: [RelayURL]) -> [(RelayURL, Bool)] {
        return relays.map({ r in
            return (r, pool.get_relay(r) == nil)
        }).sorted { (a, b) in a.0 < b.0 }
    }
    
    var body: some View {
        List(relay_state, id: \.0) { (r, add) in
            RelayView(state: state, relay: r, showActionButtons: .constant(true), recommended: true)
        }
        .listStyle(PlainListStyle())
        .navigationBarTitle(NSLocalizedString("Relays", comment: "Navigation bar title that shows the list of relays for a user."))
    }
}

struct UserRelaysView_Previews: PreviewProvider {
    static var previews: some View {
        UserRelaysView(state: test_damus_state, relays: [])
    }
}
