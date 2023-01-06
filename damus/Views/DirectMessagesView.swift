//
//  DirectMessagesView.swift
//  damus
//
//  Created by William Casarin on 2022-06-29.
//

import SwiftUI

struct DirectMessagesView: View {
    let damus_state: DamusState
    
    @State var open_dm: Bool = false
    @State var pubkey: String = ""
    @State var active_model: DirectMessageModel = DirectMessageModel()
    @EnvironmentObject var model: DirectMessagesModel
    
    var MainContent: some View {
        ScrollView {
            let chat = DMChatView(damus_state: damus_state, pubkey: pubkey)
                .environmentObject(active_model)
            NavigationLink(destination: chat, isActive: $open_dm) {
                EmptyView()
            }
            LazyVStack {
                if model.dms.isEmpty, !model.loading {
                    EmptyTimelineView()
                } else {
                    ForEach(model.dms, id: \.0) { tup in
                        MaybeEvent(tup)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }
    
    func MaybeEvent(_ tup: (String, DirectMessageModel)) -> some View {
        Group {
            if let ev = tup.1.events.last {
                EventView(damus: damus_state, event: ev, pubkey: tup.0, show_friend_icon: true)
                    .onTapGesture {
                        pubkey = tup.0
                        active_model = tup.1
                        open_dm = true
                    }
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
