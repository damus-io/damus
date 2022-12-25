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
    
    var body: some View {
        LazyVStack {
            if events.isEmpty {
                EmptyTimelineView()
            } else {
                ForEach(events.filter(filter), id: \.id) { (ev: NostrEvent) in
                    let tm = ThreadModel(event: inner_event_or_self(ev: ev), damus_state: damus)
                    let is_chatroom = should_show_chatroom(ev)
                    let tv = ThreadView(thread: tm, damus: damus, is_chatroom: is_chatroom)
                                
                    NavigationLink(destination: ThreadV2View(
                        damus: damus,
                        thread: ThreadV2(
                            parentEvents: [
                                NostrEvent(id: "1", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                                NostrEvent(id: "2", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                                NostrEvent(id: "3", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                            ],
                            current: NostrEvent(id: "4", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                            childEvents: [
                                NostrEvent(id: "5", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                                NostrEvent(id: "6", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                            ]
                        )                    )) {
                        EventView(event: ev, highlight: .none, has_action_bar: true, damus: damus, show_friend_icon: show_friend_icon)
                    }
                    .isDetailLink(true)
                    .buttonStyle(PlainButtonStyle())
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
