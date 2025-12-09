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
    let home: HomeModel

    @State var dm_type: DMType = .friend
    @ObservedObject var model: DirectMessagesModel

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
        .refreshable {
            // Fetch full DM history without the `since` optimization.
            // This allows users to manually sync older DMs that may have
            // been missed due to the optimized network filter.
            await home.fetchFullDMHistory()
        }
        .padding(.bottom, tabHeight)
    }
    
    func filter_dms(dms: [DirectMessageModel]) -> [DirectMessageModel] {
        return filter_dms_by_mute(dms: dms, mutelist_manager: damus_state.mutelist_manager)
    }
    
    var options: EventViewOptions {
        /*
        if self.damus_state.settings.translate_dms {
            return [.truncate_content, .no_action_bar]
        }
         */

        return [.truncate_content, .no_action_bar, .no_translate]
    }
    
    func MaybeEvent(_ model: DirectMessageModel) -> some View {
        Group {
            if let ev = model.events.last(where: { should_show_event(state: damus_state, ev: $0) }) {
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
            CustomPicker(tabs: [
                (NSLocalizedString("DMs", comment: "Picker option for DM selector for seeing only DMs that have been responded to. DM is the English abbreviation for Direct Message."), DMType.friend),
                (NSLocalizedString("Requests", comment: "Picker option for DM selector for seeing only message requests (DMs that someone else sent the user which has not been responded to yet"), DMType.rando),
            ], selection: $dm_type)

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
        .navigationTitle(NSLocalizedString("DMs", comment: "Navigation title for view of DMs, where DM is an English abbreviation for Direct Message."))
    }
}


/// Filters DM threads to exclude muted users.
///
/// All DM threads are shown regardless of trusted network settings.
/// Only explicitly muted users are filtered out.
@MainActor
func filter_dms_by_mute(dms: [DirectMessageModel], mutelist_manager: MutelistManager) -> [DirectMessageModel] {
    return dms.filter({ dm in
        return !mutelist_manager.is_muted(.user(dm.pubkey, nil))
    })
}

struct DirectMessagesView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state
        DirectMessagesView(damus_state: ds, home: HomeModel(), model: ds.dms)
    }
}
