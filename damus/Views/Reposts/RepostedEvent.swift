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
            NavigationLink(value: Route.ProfileByKey(pubkey: event.pubkey)) {
                Reposted(damus: damus, pubkey: event.pubkey)
                    .padding(.horizontal)
            }
           .buttonStyle(PlainButtonStyle())
            
            //SelectedEventView(damus: damus, event: inner_ev, size: .normal)
            EventMutingContainerView(
                damus_state: damus,
                event: inner_ev,
                muteBox: { event_shown, muted_reason in
                    AnyView(
                        EventMutedBoxView(shown: event_shown, reason: muted_reason)
                            .padding(.horizontal, 5)    // Add a bit of horizontal padding to avoid the mute box from touching the edges of the screen
                    )
                }) {
                EventView(damus: damus, event: inner_ev, pubkey: inner_ev.pubkey, options: options.union(.wide))
            }
        }
    }
}

struct RepostedEvent_Previews: PreviewProvider {
    static var previews: some View {
        RepostedEvent(damus: test_damus_state, event: test_note, inner_ev: test_note, options: [])
    }
}
