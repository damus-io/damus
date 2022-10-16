//
//  DMView.swift
//  damus
//
//  Created by William Casarin on 2022-07-01.
//

import SwiftUI

struct DMView: View {
    let event: NostrEvent
    let damus_state: DamusState
    
    var is_ours: Bool {
        event.pubkey == damus_state.pubkey
    }
    
    var body: some View {
        HStack {
            if is_ours {
                Spacer()
            }
            
            NoteContentView(privkey: damus_state.keypair.privkey, event: event, profiles: damus_state.profiles, show_images: true, content: event.get_content(damus_state.keypair.privkey))
                .foregroundColor(is_ours ? Color.white : Color.primary)
                .padding(10)
                .background(is_ours ? Color.accentColor : Color.secondary.opacity(0.15))
                .cornerRadius(8.0)
                .tint(is_ours ? Color.white : Color.accentColor)
        }
    }
}

struct DMView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "Hey there *buddy*, want to grab some drinks later? 🍻", pubkey: "pubkey", kind: 1, tags: [])
        DMView(event: ev, damus_state: test_damus_state())
    }
}
