//
//  RepostedEvent.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import SwiftUI

struct RepostedEvent: View {
    let damus: DamusState
    let event: NostrEvent
    let inner_ev: NostrEvent
    let options: EventViewOptions
    
    var body: some View {
        VStack(alignment: .leading) {
            let prof = damus.profiles.lookup(id: event.pubkey)
            let booster_profile = ProfileView(damus_state: damus, pubkey: event.pubkey)
            
            NavigationLink(destination: booster_profile) {
                Reposted(damus: damus, pubkey: event.pubkey, profile: prof)
                    .padding(.horizontal)
            }
           .buttonStyle(PlainButtonStyle())
            
            //SelectedEventView(damus: damus, event: inner_ev, size: .normal)
            TextEvent(damus: damus, event: inner_ev, pubkey: inner_ev.pubkey, options: options)
        }
    }
}

struct RepostedEvent_Previews: PreviewProvider {
    static var previews: some View {
        RepostedEvent(damus: test_damus_state(), event: test_event, inner_ev: test_event, options: [])
    }
}
