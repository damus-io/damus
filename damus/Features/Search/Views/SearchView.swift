//
//  SearchView.swift
//  damus
//
//  Created by William Casarin on 2022-05-09.
//

import SwiftUI

struct SearchView: View {
    let appstate: DamusState
    @ObservedObject var search: SearchModel
    @Environment(\.dismiss) var dismiss
    @State var is_hashtag_muted: Bool = false

    var content_filter: (NostrEvent) -> Bool {
        let filters = ContentFilters.defaults(damus_state: self.appstate)
        return ContentFilters(filters: filters).filter
    }

    let height: CGFloat = 250.0

    var body: some View {
        TimelineView(events: search.events, loading: $search.loading, damus: appstate, show_friend_icon: true, filter: content_filter) {
            ZStack(alignment: .leading) {
                DamusBackground(maxHeight: height)
                    .mask(LinearGradient(gradient: Gradient(colors: [.black, .black, .black, .clear]), startPoint: .top, endPoint: .bottom))
                SearchHeaderView(state: appstate, described: described_search)
                    .padding(.leading, 30)
                    .padding(.top, 100)
            }
        }
        .ignoresSafeArea()
        .onReceive(handle_notify(.switched_timeline)) { obj in
            dismiss()
        }
        .onAppear() {
            search.subscribe()
        }
        .onDisappear() {
            search.unsubscribe()
        }
        .onReceive(handle_notify(.new_mutes)) { notif in
            search.filter_muted()

            if let hashtag_string = search.search.hashtag?.first,
               notif.contains(MuteItem.hashtag(Hashtag(hashtag: hashtag_string), nil)) {
                is_hashtag_muted = true
            }
        }
        .onReceive(handle_notify(.new_unmutes)) { unmutes in
            if let hashtag_string = search.search.hashtag?.first,
               unmutes.contains(MuteItem.hashtag(Hashtag(hashtag: hashtag_string), nil)) {
                is_hashtag_muted = false
            }
        }
        .toolbar {
            if let hashtag = search.search.hashtag?.first {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if is_hashtag_muted {
                            Button {
                                guard
                                    let full_keypair = appstate.keypair.to_full(),
                                    let existing_mutelist = appstate.mutelist_manager.event,
                                    let mutelist = remove_from_mutelist(keypair: full_keypair, prev: existing_mutelist, to_remove: .hashtag(Hashtag(hashtag: hashtag), nil))
                                else {
                                    return
                                }

                                appstate.mutelist_manager.set_mutelist(mutelist)
                                appstate.settings.latest_mutelist_event_id_hex = mutelist.id.hex()
                                Task { await appstate.nostrNetwork.postbox.send(mutelist) }
                            } label: {
                                Text("Unmute Hashtag", comment: "Label represnting a button that the user can tap to unmute a given hashtag so they start seeing it in their feed again.")
                            }
                        } else {
                            MuteDurationMenu { duration in
                                mute_hashtag(hashtag_string: hashtag, expiration_time: duration?.date_from_now)
                            } label: {
                                Text("Mute Hashtag", comment: "Label represnting a button that the user can tap to mute a given hashtag so they don't see it in their feed anymore.")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .onAppear {
            if let hashtag_string = search.search.hashtag?.first {
                is_hashtag_muted = (appstate.mutelist_manager.event?.mute_list ?? []).contains(MuteItem.hashtag(Hashtag(hashtag: hashtag_string), nil))
            }
        }
    }

    func mute_hashtag(hashtag_string: String, expiration_time: Date?) {
        let existing_mutelist = appstate.mutelist_manager.event

        guard
            let full_keypair = appstate.keypair.to_full(),
            let mutelist = create_or_update_mutelist(keypair: full_keypair, mprev: existing_mutelist, to_add: .hashtag(Hashtag(hashtag: hashtag_string), expiration_time))
        else {
            return
        }

        appstate.mutelist_manager.set_mutelist(mutelist)
        appstate.settings.latest_mutelist_event_id_hex = mutelist.id.hex()
        Task { await appstate.nostrNetwork.postbox.send(mutelist) }
    }

    var described_search: DescribedSearch {
        return describe_search(search.search)
    }
}

enum DescribedSearch: CustomStringConvertible {
    case hashtag(String)
    case unknown

    var is_hashtag: String? {
        switch self {
        case .hashtag(let ht):
            return ht
        case .unknown:
            return nil
        }
    }

    var description: String {
        switch self {
        case .hashtag(let s):
            return "#" + s
        case .unknown:
            return NSLocalizedString("Search", comment: "Default title for the search screen when it is in an unknown state.")
        }
    }
}

func describe_search(_ filter: NostrFilter) -> DescribedSearch {
    if let hashtags = filter.hashtag {
        if hashtags.count >= 1 {
            return .hashtag(hashtags[0])
        }
    }

    return .unknown
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        let test_state = test_damus_state
        let filter = NostrFilter(hashtag: ["bitcoin"])
        
        let model = SearchModel(state: test_state, search: filter)
        
        SearchView(appstate: test_state, search: model)
    }
}
