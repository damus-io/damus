//
//  PostingTimelineView.swift
//  damus
//
//  Created by eric on 7/15/24.
//

import SwiftUI

struct PostingTimelineView: View {
    
    let damus_state: DamusState
    var home: HomeModel
    @State var search: String = ""
    @State var results: [NostrEvent] = []
    @State var initialOffset: CGFloat?
    @State var offset: CGFloat?
    @State var showSearch: Bool = true
    @Binding var active_sheet: Sheets?
    @FocusState private var isSearchFocused: Bool
    @State private var contentOffset: CGFloat = 0
    @State private var indicatorWidth: CGFloat = 0
    @State private var indicatorPosition: CGFloat = 0
    @SceneStorage("PostingTimelineView.filter_state") var filter_state : FilterState = .posts_and_replies
    
    var mystery: some View {
        Text("Are you lost?", comment: "Text asking the user if they are lost in the app.")
        .id("what")
    }

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)
        return ContentFilters(filters: filters).filter
    }
    
    func contentTimelineView(filter: (@escaping (NostrEvent) -> Bool)) -> some View {
        TimelineView(events: home.events, loading: .constant(false), damus: damus_state, show_friend_icon: false, filter: filter) {
            PullDownSearchView(state: damus_state, on_cancel: {})
        }
    }

    var body: some View {
        VStack {
            ZStack {
                TabView(selection: $filter_state) {
                    // This is needed or else there is a bug when switching from the 3rd or 2nd tab to first. no idea why.
                    mystery
                    
                    contentTimelineView(filter: content_filter(.posts))
                        .tag(FilterState.posts)
                        .id(FilterState.posts)
                    contentTimelineView(filter: content_filter(.posts_and_replies))
                        .tag(FilterState.posts_and_replies)
                        .id(FilterState.posts_and_replies)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                if damus_state.keypair.privkey != nil {
                    PostButtonContainer(is_left_handed: damus_state.settings.left_handed) {
                        self.active_sheet = .post(.posting(.none))
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CustomPicker(tabs: [
                    (NSLocalizedString("Notes", comment: "Label for filter for seeing only notes (instead of notes and replies)."), FilterState.posts),
                    (NSLocalizedString("Notes & Replies", comment: "Label for filter for seeing notes and replies (instead of only notes)."), FilterState.posts_and_replies)
                  ],
                selection: $filter_state)

                Divider()
                    .frame(height: 1)
            }
            .background(DamusColors.adaptableWhite)
        }
    }
}
