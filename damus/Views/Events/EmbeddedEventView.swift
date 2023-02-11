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
            HStack {
                EventProfile(damus_state: damus_state, pubkey: pubkey, profile: profile, size: .small)
                
                Spacer()
                
                EventMenuContext(event: event, keypair: damus_state.keypair, target_pubkey: event.pubkey)
                    .padding([.bottom], 4)

            }
            .minimumScaleFactor(0.75)
            .lineLimit(1)
            
            EventBody(damus_state: damus_state, event: event, size: .small)
        }
    }
}

struct EmbeddedEventView_Previews: PreviewProvider {
    static var previews: some View {
        EmbeddedEventView(damus_state: test_damus_state(), event: test_event)
            .padding()
    }
}
