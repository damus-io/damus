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
    @ObservedObject var model: DirectMessagesModel
    @ObservedObject var settings: UserSettingsStore
    
    func MainContent(requests: Bool) -> some View {
        ScrollView {
            let chat = DMChatView(damus_state: damus_state, dms: model.active_model)
            NavigationLink(destination: chat, isActive: $model.open_dm) {
                EmptyView()
            }
            LazyVStack(spacing: 0) {
                if model.dms.isEmpty, !model.loading {
                    EmptyTimelineView()
                } else {
                    let dms = requests ? model.message_requests : model.friend_dms
                    ForEach(dms, id: \.pubkey) { dm in
                        MaybeEvent(dm)
                            .padding(.top, 10)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    var options: EventViewOptions {
        if self.damus_state.settings.translate_dms {
            return [.truncate_content, .no_action_bar]
        }
        
        return [.truncate_content, .no_action_bar, .no_translate]
    }
    
    func MaybeEvent(_ model: DirectMessageModel) -> some View {
        Group {
            let ok = damus_state.settings.friend_filter.filter(contacts: damus_state.contacts, pubkey: model.pubkey)
            if ok, let ev = model.events.last {
                EventView(damus: damus_state, event: ev, pubkey: model.pubkey, options: options)
                    .onTapGesture {
                        self.model.open_dm_by_model(model)
                    }
                
                Divider()
                    .padding([.top], 10)
            } else {
                EmptyView()
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            CustomPicker(selection: $dm_type, content: {
                Text("DMs", comment: "Picker option for DM selector for seeing only DMs that have been responded to. DM is the English abbreviation for Direct Message.")
                    .tag(DMType.friend)
                Text("Requests", comment: "Picker option for DM selector for seeing only message requests (DMs that someone else sent the user which has not been responded to yet). DM is the English abbreviation for Direct Message.")
                    .tag(DMType.rando)
            })
            
            Divider()
                .frame(height: 1)
            
            TabView(selection: $dm_type) {
                MainContent(requests: false)
                    .tag(DMType.friend)
                
                MainContent(requests: true)
                    .tag(DMType.rando)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if would_filter_non_friends_from_dms(contacts: damus_state.contacts, dms: self.model.dms) {
                    
                    FriendsButton(filter: $settings.friend_filter)
                }
            }
        }
        .navigationTitle(NSLocalizedString("DMs", comment: "Navigation title for view of DMs, where DM is an English abbreviation for Direct Message."))
    }
}

func would_filter_non_friends_from_dms(contacts: Contacts, dms: [DirectMessageModel]) -> Bool {
    for dm in dms {
        if !FriendFilter.friends.filter(contacts: contacts, pubkey: dm.pubkey) {
            return true
        }
    }
    
    return false
}

struct DirectMessagesView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        DirectMessagesView(damus_state: ds, model: ds.dms, settings: ds.settings)
    }
}
