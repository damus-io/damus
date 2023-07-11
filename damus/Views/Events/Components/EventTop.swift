//
//  EventTop.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct EventTop: View {
    let state: DamusState
    let event: NostrEvent
    let pubkey: String
    let is_anon: Bool
    
    init(state: DamusState, event: NostrEvent, pubkey: String, is_anon: Bool) {
        self.state = state
        self.event = event
        self.pubkey = pubkey
        self.is_anon = is_anon
    }
    
    func ProfileName(is_anon: Bool) -> some View {
        let profile = state.profiles.lookup(id: self.pubkey)
        let pk = is_anon ? "anon" : self.pubkey
        return EventProfileName(pubkey: pk, profile: profile, damus: state, size: .normal)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ProfileName(is_anon: is_anon)
            TimeDot()
            RelativeTime(time: state.events.get_cache_data(event.id).relative_time)
            Spacer()
            EventMenuContext(damus: state, event: event)
        }
        
        .lineLimit(1)
    }
}

struct EventTop_Previews: PreviewProvider {
    static var previews: some View {
        EventTop(state: test_damus_state(), event: test_event, pubkey: test_event.pubkey, is_anon: false)
    }
}
