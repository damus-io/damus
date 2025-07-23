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
    @Binding var isSideBarOpened: Bool
    @Binding var active_sheet: Sheets?
    @FocusState private var isSearchFocused: Bool
    @State private var contentOffset: CGFloat = 0
    @State private var indicatorWidth: CGFloat = 0
    @State private var indicatorPosition: CGFloat = 0
    @State var headerHeight: CGFloat = 0
    @Binding var headerOffset: CGFloat
    @SceneStorage("PostingTimelineView.filter_state") var filter_state : FilterState = .posts_and_replies

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)
        return ContentFilters(filters: filters).filter
    }
    
    func contentTimelineView(filter: (@escaping (NostrEvent) -> Bool)) -> some View {
        TimelineView<AnyView>(events: home.events, loading: .constant(false), headerHeight: $headerHeight, headerOffset: $headerOffset, damus: damus_state, show_friend_icon: false, filter: filter)
    }
    
    func HeaderView()->some View {
        VStack {
            VStack(spacing: 0) {
                // This is needed for the Dynamic Island
                HStack {}
                .frame(height: getSafeAreaTop())
                
                HStack(alignment: .top) {
                    TopbarSideMenuButton(damus_state: damus_state, isSideBarOpened: $isSideBarOpened)
                    
                    Spacer()
                    
                    Image("damus-home")
                        .resizable()
                        .frame(width:30,height:30)
                        .shadow(color: DamusColors.purple, radius: 2)
                        .opacity(isSideBarOpened ? 0 : 1)
                        .animation(isSideBarOpened ? .none : .default, value: isSideBarOpened)
                        .onTapGesture {
                            isSideBarOpened.toggle()
                        }
                        .padding(.leading)
                    
                    Spacer()
                    
                    HStack(alignment: .center) {
                        SignalView(state: damus_state, signal: home.signal)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                CustomPicker(tabs: [
                    (NSLocalizedString("Notes", comment: "Label for filter for seeing only notes (instead of notes and replies)."), FilterState.posts),
                    (NSLocalizedString("Notes & Replies", comment: "Label for filter for seeing notes and replies (instead of only notes)."), FilterState.posts_and_replies)
                ],
                             selection: $filter_state)
                
                Divider()
                    .frame(height: 1)
            }
        }
        .background {
            DamusColors.adaptableWhite
                .ignoresSafeArea()
        }
    }

    var body: some View {
        VStack {
            ZStack {
                TabView(selection: $filter_state) {
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
                    .padding(.bottom, tabHeight + getSafeAreaBottom())
                    .opacity(0.35 + abs(1.25 - (abs(headerOffset/100.0))))
                }
            }
        }
        .overlay(alignment: .top) {
            HeaderView()
                .anchorPreference(key: HeaderBoundsKey.self, value: .bounds){$0}
                .overlayPreferenceValue(HeaderBoundsKey.self) { value in
                    GeometryReader{ proxy in
                        if let anchor = value{
                            Color.clear
                                .onAppear {
                                    headerHeight = proxy[anchor].height
                                }
                        }
                    }
                }
                .offset(y: -headerOffset < headerHeight ? headerOffset : (headerOffset < 0 ? headerOffset : 0))
                .opacity(1.0 - (abs(headerOffset/100.0)))
        }
    }
}
