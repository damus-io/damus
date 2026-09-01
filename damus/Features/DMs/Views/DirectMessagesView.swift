//
//  DirectMessagesView.swift
//  damus
//
//  Created by William Casarin on 2022-06-29.
//

import SwiftUI
import TipKit

enum DMType: Hashable {
    case rando
    case friend
}

extension DMType {
    /// The labelled options the DM filter selector offers.
    ///
    /// Shared by the top ``CustomPicker`` and the tab view's bottom accessory —
    /// only one of the two is on screen at a time, but they must offer the same
    /// options in the same order, so the labels live in one place.
    static var timeline_filter_options: [(String, DMType)] {
        [
            (NSLocalizedString("DMs", comment: "Picker option for DM selector for seeing only DMs that have been responded to. DM is the English abbreviation for Direct Message."), .friend),
            (NSLocalizedString("Requests", comment: "Picker option for DM selector for seeing only message requests (DMs that someone else sent the user which has not been responded to yet"), .rando),
        ]
    }
}

struct DirectMessagesView: View {
    let damus_state: DamusState
    let home: HomeModel

    /// Which of the two DM lists to show.
    ///
    /// Owned by ``ContentView`` rather than by this view, because on iOS 26 the
    /// selector for it is the tab view's bottom accessory, which attaches to the
    /// `TabView` and so cannot reach state that lives in here.
    @Binding var dm_type: DMType
    @ObservedObject var model: DirectMessagesModel
    @ObservedObject var settings: UserSettingsStore
    @Binding var subtitle: String?

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
    }
    
    func filter_dms(dms: [DirectMessageModel]) -> [DirectMessageModel] {
        return dms.filter({ dm in
            return damus_state.settings.friend_filter.filter(contacts: damus_state.contacts, pubkey: dm.pubkey) && !damus_state.mutelist_manager.is_muted(.user(dm.pubkey, nil))
        })
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
        let showTrustedButton = would_filter_non_friends_from_dms(contacts: damus_state.contacts, dms: self.model.dms)
        VStack(spacing: 0) {
            if #available(iOS 17, *), showTrustedButton {
                TipView(TrustedNetworkButtonTip.shared)
                    .tipBackground(.clear)
                    .tipViewStyle(TrustedNetworkButtonTipViewStyle())
                    .padding(.horizontal)
            }

            if !timelineFilterLivesInTabViewAccessory {
                CustomPicker(tabs: DMType.timeline_filter_options, selection: $dm_type)

                Divider()
                    .frame(height: 1)
            }

            // Driven by the filter selector: the `CustomPicker` above pre-26,
            // the tab view's bottom glass accessory from iOS 26 on. This used to
            // be a paged `TabView`, which the iOS 26 tab bar cannot see through:
            // a paged `TabView` neither reports its scrolling to the enclosing
            // tab bar (so the bar never minimized on this tab) nor lets content
            // run under the floating bar (leaving an opaque `adaptableWhite`
            // slab where the timeline should show through the glass). Rendering
            // the selected list directly hands the real `ScrollView` to the tab
            // bar. The cost is the swipe-between-filters gesture, which the
            // selector already duplicates.
            MainContent(requests: dm_type == .rando)
                .id(dm_type)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if showTrustedButton {
                    TrustedNetworkButton(filter: $settings.friend_filter) {
                        if #available(iOS 17, *) {
                            TrustedNetworkButtonTip.shared.invalidate(reason: .actionPerformed)
                        }
                    }
                }
            }
        }
        .onAppear {
            self.subtitle = settings.friend_filter.description()

        }
        .onChange(of: settings.friend_filter) { val in
            self.subtitle = val.description()
        }
        .navigationTitle(NSLocalizedString("DMs", comment: "Navigation title for view of DMs, where DM is an English abbreviation for Direct Message."))
    }
}

@MainActor
func would_filter_non_friends_from_dms(contacts: Contacts, dms: [DirectMessageModel]) -> Bool {
    for dm in dms {
        if !FriendFilter.friends_of_friends.filter(contacts: contacts, pubkey: dm.pubkey) {
            return true
        }
    }
    
    return false
}

struct DirectMessagesView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state
        DirectMessagesView(damus_state: ds, home: HomeModel(), dm_type: .constant(.friend), model: ds.dms, settings: ds.settings, subtitle: .constant(nil))
    }
}
