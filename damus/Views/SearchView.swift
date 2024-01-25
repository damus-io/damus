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
        }
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
            return "Search"
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
