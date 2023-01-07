//
//  TimelineView.swift
//  damus
//
//  Created by William Casarin on 2022-04-18.
//

import SwiftUI

enum TimelineAction {
    case chillin
    case navigating
}

struct InnerTimelineView: View {
    @Binding var events: [NostrEvent]
    let damus: DamusState
    let show_friend_icon: Bool
    let filter: (NostrEvent) -> Bool
    @State var nav_target: NostrEvent? = nil
    @State var navigating: Bool = false
    
    var MaybeBuildThreadView: some View {
        Group {
            if let ev = nav_target {
                BuildThreadV2View(damus: damus, event_id: (ev.inner_event ?? ev).id)
            } else {
                EmptyView()
            }
        }
    }
    
    var body: some View {
        NavigationLink(destination: MaybeBuildThreadView, isActive: $navigating) {
            EmptyView()
        }
        LazyVStack {
            if events.isEmpty {
                EmptyTimelineView()
            } else {
                ForEach(events.filter(filter), id: \.id) { (ev: NostrEvent) in
                    //let tm = ThreadModel(event: inner_event_or_self(ev: ev), damus_state: damus)
                    //let is_chatroom = should_show_chatroom(ev)
                    //let tv = ThreadView(thread: tm, damus: damus, is_chatroom: is_chatroom)
                                
                    EventView(event: ev, highlight: .none, has_action_bar: true, damus: damus, show_friend_icon: show_friend_icon)
                        .onTapGesture {
                            nav_target = ev
                            navigating = true
                        }
                }
            }
        }
        .padding(.horizontal)
    }
}

struct TimelineView: View {
    
    @Binding var events: [NostrEvent]
    @Binding var loading: Bool

    let damus: DamusState
    let show_friend_icon: Bool
    let filter: (NostrEvent) -> Bool
    
    var body: some View {
        MainContent
    }
    
    var MainContent: some View {
        ScrollViewReader { scroller in
            ScrollView {
                InnerTimelineView(events: loading ? .constant(Constants.EXAMPLE_EVENTS) : $events, damus: damus, show_friend_icon: show_friend_icon, filter: loading ? { _ in true } : filter)
                    .redacted(reason: loading ? .placeholder : [])
                    .shimmer(loading)
                    .disabled(loading)
            }
            .onReceive(NotificationCenter.default.publisher(for: .scroll_to_top)) { _ in
                guard let event = events.filter(self.filter).first else {
                    return
                }
                scroll_to_event(scroller: scroller, id: event.id, delay: 0.0, animate: true)
            }
        }
    }
}

struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView(events: .constant(Constants.EXAMPLE_EVENTS), loading: .constant(true), damus: Constants.EXAMPLE_DEMOS, show_friend_icon: true, filter: { _ in true })
    }
}


struct NavigationLazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}
