//
//  EmbeddedEventView.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

struct EmbeddedEventView: View {
    let damus_state: DamusState
    let event: NostrEvent
    
    var pubkey: String {
        event.pubkey
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            let profile = damus_state.profiles.lookup(id: pubkey)
            
            EventProfile(damus_state: damus_state, pubkey: pubkey, profile: profile, size: .small)
            
            EventBody(damus_state: damus_state, event: event, size: .small)
        }
        .event_context_menu(event, privkey: damus_state.keypair.privkey, pubkey: pubkey)
    }
}

struct EmbeddedEventView_Previews: PreviewProvider {
    static var previews: some View {
        EmbeddedEventView(damus_state: test_damus_state(), event: test_event)
            .padding()
    }
}
