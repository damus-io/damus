//
//  DirectMessagesView.swift
//  damus
//
//  Created by William Casarin on 2022-06-29.
//

import SwiftUI

enum DMType: Hashable {
    case rando
    case friend
}

struct DirectMessagesView: View {
    let damus_state: DamusState
    
    @State var dm_type: DMType = .friend
    @State var open_dm: Bool = false
    @State var pubkey: String = ""
    @EnvironmentObject var model: DirectMessagesModel
    @State var active_model: DirectMessageModel
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        self._active_model = State(initialValue: DirectMessageModel(our_pubkey: damus_state.pubkey))
    }
    
    func MainContent(requests: Bool) -> some View {
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
                    let dms = requests ? model.message_requests : model.friend_dms
                    ForEach(dms, id: \.0) { tup in
                        MaybeEvent(tup)
                    }
                }
            }
        }
    }
    
    func MaybeEvent(_ tup: (String, DirectMessageModel)) -> some View {
        Group {
            if let ev = tup.1.events.last {
                EventView(damus: damus_state, event: ev, pubkey: tup.0)
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
        VStack {
            Picker(NSLocalizedString("DM Type", comment: "DM selector for seeing either DMs or message requests, which are messages that have not been responded to yet. DM is the English abbreviation for Direct Message."), selection: $dm_type) {
                Text("DMs", comment: "Picker option for DM selector for seeing only DMs that have been responded to. DM is the English abbreviation for Direct Message.")
                    .tag(DMType.friend)
                
                Text("Requests", comment: "Picker option for DM selector for seeing only message requests (DMs that someone else sent the user which has not been responded to yet). DM is the English abbreviation for Direct Message.")
                    .tag(DMType.rando)
                
            }
            .pickerStyle(.segmented)
            
            TabView(selection: $dm_type) {
                MainContent(requests: false)
                    .tag(DMType.friend)
                
                MainContent(requests: true)
                    .tag(DMType.rando)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .padding(.horizontal)
        .padding(.top)
        .navigationTitle(NSLocalizedString("DMs", comment: "Navigation title for view of DMs, where DM is an English abbreviation for Direct Message."))
    }
}

struct DirectMessagesView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "encrypted stuff",
                               pubkey: "pubkey",
                               kind: 4,
                               tags: [])
        let ds = test_damus_state()
        let model = DirectMessageModel(events: [ev], our_pubkey: ds.pubkey)
        DirectMessagesView(damus_state: ds)
            .environmentObject(model)
    }
}
