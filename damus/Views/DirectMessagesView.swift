//
//  DirectMessagesView.swift
//  damus
//
//  Created by William Casarin on 2022-06-29.
//

import SwiftUI

struct DirectMessagesView: View {
    let damus_state: DamusState
    @EnvironmentObject var model: DirectMessagesModel
    
    var MainContent: some View {
        ScrollView {
            LazyVStack {
                ForEach(model.dms, id: \.0) { tup in
                    MaybeEvent(tup)
                }
            }
        }
    }
    
    func MaybeEvent(_ tup: (String, DirectMessageModel)) -> some View {
        Group {
            if let ev = tup.1.events.last {
                let chat = DMChatView(damus_state: damus_state, pubkey: tup.0)
                    .environmentObject(tup.1)
                NavigationLink(destination: chat) {
                    EventView(damus: damus_state, event: ev, pubkey: tup.0, show_friend_icon: true)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                EmptyView()
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
        let model = DirectMessageModel(events: [ev])
        DirectMessagesView(damus_state: test_damus_state())
            .environmentObject(model)
    }
}
