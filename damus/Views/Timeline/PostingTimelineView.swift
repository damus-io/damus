//
//  PostingTimelineView.swift
//  damus
//
//  Created by eric on 3/21/24.
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
    @SceneStorage("ContentView.filter_state") var filter_state : FilterState = .posts_and_replies
    
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
        VStack(spacing: 0) {
            if self.showSearch {
                PullDownSearchView(state: damus_state, search_text: $search, results: $results)
                    .focused($isSearchFocused)
            }
            if !isSearchFocused && search.isEmpty {
                TimelineView(events: home.events, loading: .constant(false), damus: damus_state, show_friend_icon: false, filter: filter) {
                    GeometryReader { geometry in
                        Color.clear.preference(key: OffsetKey.self, value: geometry.frame(in: .global).minY)
                            .frame(height: 0)
                    }
                }
            } else {
                SearchContentView(state: damus_state, search_text: $search, results: $results)
                    .padding(.top)
                    .scrollDismissesKeyboard(.immediately)
            }
        }
        .onPreferenceChange(OffsetKey.self) {
            if self.initialOffset == nil || self.initialOffset == 0 {
                self.initialOffset = $0
            }
            
            self.offset = $0
            
            guard let initialOffset = self.initialOffset,
                  let offset = self.offset else {
                return
            }
            
            if(initialOffset > offset){
                self.showSearch = false
            } else {
                self.showSearch = true
            }
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
                
                if damus_state.keypair.privkey != nil && (!isSearchFocused && search.isEmpty) {
                    PostButtonContainer(is_left_handed: damus_state.settings.left_handed) {
                        active_sheet = .post(.posting(.none))
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !isSearchFocused && search.isEmpty {
                VStack(spacing: 0) {
                    CustomPicker(selection: $filter_state, content: {
                        Text("Notes", comment: "Filter label for seeing only notes (instead of notes and replies).").tag(FilterState.posts)
                        Text("Notes & Replies", comment: "Filter label for seeing notes and replies (instead of only notes).").tag(FilterState.posts_and_replies)
                    })
                    Divider()
                        .frame(height: 1)
                }
                .background(DamusColors.adaptableWhite)
                .transition(.opacity)
            }
        }
    }
}

struct OffsetKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?,
                       nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
}

struct PostingTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        let home: HomeModel = HomeModel()
        PostingTimelineView(damus_state: test_damus_state, home: home, active_sheet: .constant(.none))
    }
}
