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
    @SceneStorage("ContentView.selected_timeline") var selected_timeline: Timeline = .home

    func MainContent(requests: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let dms = requests ? model.message_requests : model.friend_dms
                let filtered_dms = filter_dms(dms: dms)
                if filtered_dms.isEmpty, !model.loading {
                    EmptyTimelineView()
                } else {
                    ForEach(filtered_dms, id: \.pubkey) { dm in
                        MaybeEvent(dm)
                            .padding(.top, 10)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    func filter_dms(dms: [DirectMessageModel]) -> [DirectMessageModel] {
        return dms.filter({ dm in
            return damus_state.settings.friend_filter.filter(contacts: damus_state.contacts, pubkey: dm.pubkey) && !damus_state.contacts.is_muted(dm.pubkey)
        })
    }
    
    var options: EventViewOptions {
        if self.damus_state.settings.translate_dms {
            return [.truncate_content, .no_action_bar]
        }
        
        return [.truncate_content, .no_action_bar, .no_translate]
    }
    
    func MaybeEvent(_ model: DirectMessageModel) -> some View {
        Group {
            if let ev = model.events.last {
                EventView(damus: damus_state, event: ev, pubkey: model.pubkey, options: options)
                    .onTapGesture {
                        self.model.set_active_dm_model(model)
                        damus_state.nav.push(route: Route.DMChat(dms: self.model.active_model))
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
            if selected_timeline == .dms {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if would_filter_non_friends_from_dms(contacts: damus_state.contacts, dms: self.model.dms) {

                        FriendsButton(filter: $settings.friend_filter)
                    }
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
        let ds = test_damus_state
        DirectMessagesView(damus_state: ds, model: ds.dms, settings: ds.settings)
    }
}
