//
//  DirectMessagesView.swift
//  damus
//
//  Created by William Casarin on 2022-06-29.
//

import SwiftUI

struct DirectMessagesView: View {
    let damus_state: DamusState
    @Binding var dms: [(String, [NostrEvent])]
    
    var MainContent: some View {
        ScrollView {
            VStack {
                ForEach(dms, id: \.0) { tup in
                    let evs = Binding<[NostrEvent]>.init(
                        get: { tup.1 },
                        set: { _ in }
                    )
                    let chat = DMChatView(damus_state: damus_state, pubkey: tup.0, events: evs)
                    NavigationLink(destination: chat) {
                        EventView(damus: damus_state, event: tup.1.last!, pubkey: tup.0)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    var body: some View {
        MainContent
            .navigationTitle("Encrypted DMs")
    }
}

struct DirectMessagesView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "encrypted stuff",
                               pubkey: "pubkey",
                               kind: 4,
                               tags: [])
        let dms = Binding<[(String, [NostrEvent])]>.init(
            get: {
                return [ ("pubkey", [ ev ]) ]
            },
            set: { _ in }
        )
        DirectMessagesView(damus_state: test_damus_state(), dms: dms)
    }
}
