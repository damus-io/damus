//
//  PostingTimelineView.swift
//  damus
//
//  Created by eric on 7/15/24.
//

import SwiftUI
import TipKit

struct PostingTimelineView: View {
    
    let damus_state: DamusState
    @ObservedObject var home: HomeModel
    /// Set this to `home.events`. This is separate from `home` because we need the events object to be directly observed so that we get instant view updates
    @ObservedObject var homeEvents: EventHolder
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
    @State var timeline_source: TimelineSource = .follows
    
    @State private var damusTips: Any? = {
        if #available(iOS 18.0, *) {
            return TipGroup(.ordered) {
                TrustedNetworkButtonTip.shared
                TrustedNetworkRepliesTip.shared
                PostingTimelineSwitcherView.TimelineSwitcherTip.shared
            }
        }
        return nil
    }()

    var loading: Binding<Bool> {
        Binding(get: {
            return home.loading
        }, set: {
            home.loading = $0
        })
    }

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)

        // If favourites feature is disabled, always use follows
        let sourceToUse = damus_state.settings.enable_favourites_feature ? timeline_source : .follows

        // Only apply friend_filter for follows timeline
        // Favorites timeline uses a dedicated EventHolder (favoriteEvents) that already contains only favorited users' events
        if sourceToUse == .follows {
            filters.append(damus_state.contacts.friend_filter)
        }
        return ContentFilters(filters: filters).filter
    }
    
    func contentTimelineView(filter: (@escaping (NostrEvent) -> Bool)) -> some View {
        let eventsSource = timeline_source == .favorites ? home.favoriteEvents : home.events
        return TimelineView<AnyView>(events: eventsSource, loading: self.loading, headerHeight: $headerHeight, headerOffset: $headerOffset, damus: damus_state, show_friend_icon: false, filter: filter, viewId: timeline_source)
    }
    
    func HeaderView() -> some View {
        VStack {
            VStack(spacing: 0) {
                // This is needed for the Dynamic Island
                HStack {}
                .frame(height: getSafeAreaTop())

                HStack(alignment: .center) {
                    TopbarSideMenuButton(damus_state: damus_state, isSideBarOpened: $isSideBarOpened)

                    Spacer()

                    HStack(alignment: .center) {
                        SignalView(state: damus_state, signal: home.signal)
                        if damus_state.settings.enable_favourites_feature {
                            Image(systemName: "square.stack")
                                .foregroundColor(DamusColors.purple)
                                .overlay(PostingTimelineSwitcherView(
                                    damusState: damus_state,
                                    timelineSource: $timeline_source
                                ))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .overlay {
                    VStack(spacing: 2) {
                        Image("damus-home")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .shadow(color: DamusColors.purple, radius: 2)
                        if damus_state.settings.enable_favourites_feature {
                            Text(timeline_source == .favorites ? timeline_source.description : " ")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .opacity(timeline_source == .favorites ? 1 : 0)
                        }
                    }
                    .opacity(isSideBarOpened ? 0 : 1)
                    .animation(isSideBarOpened ? .none : .default, value: isSideBarOpened)
                    .onTapGesture {
                        isSideBarOpened.toggle()
                    }
                }
            }
            .padding(.horizontal, 20)
            if #available(iOS 18.0, *), let tipGroup = damusTips as? TipGroup {
                TipView(tipGroup.currentTip as? PostingTimelineSwitcherView.TimelineSwitcherTip)
                    .tipBackground(.clear)
                    .tipViewStyle(TrustedNetworkButtonTipViewStyle())
                    .padding(.horizontal)
            }

            CustomPicker(tabs: [
                (NSLocalizedString("Notes", comment: "Label for filter for seeing only notes (instead of notes and replies)."), FilterState.posts),
                (NSLocalizedString("Notes & Replies", comment: "Label for filter for seeing notes and replies (instead of only notes)."), FilterState.posts_and_replies)
            ],
                         selection: $filter_state)

            Divider()
                .frame(height: 1)
        }
        .background {
            DamusColors.adaptableWhite
                .ignoresSafeArea()
        }
    }

    var body: some View {
        VStack {
            timelineBody
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

private extension PostingTimelineView {
    var timelineBody: some View {
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
}

struct PostingTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        PostingTimelineView(
            damus_state: test_damus_state,
            home: HomeModel(),
            homeEvents: .init(),
            isSideBarOpened: .constant(false),
            active_sheet: .constant(nil),
            headerOffset: .constant(0)
        )
    }
}
