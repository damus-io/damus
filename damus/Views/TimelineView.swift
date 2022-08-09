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
    
    var body: some View {
        LazyVStack {
            ForEach(events, id: \.id) { (ev: NostrEvent) in
                let tv = ThreadView(thread: ThreadModel(event: ev, pool: damus.pool, privkey: damus.keypair.privkey), damus: damus, is_chatroom: has_hashtag(ev.tags, hashtag: "chat"))
                            
                NavigationLink(destination: tv) {
                    EventView(event: ev, highlight: .none, has_action_bar: true, damus: damus, show_friend_icon: show_friend_icon)
                }
                .isDetailLink(true)
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct TimelineView: View {
    @Binding var events: [NostrEvent]
    @Binding var loading: Bool

    let damus: DamusState
    let show_friend_icon: Bool
    
    var body: some View {
        MainContent
    }
    
    var MainContent: some View {
        ScrollViewReader { scroller in
            ScrollView {
                if loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                InnerTimelineView(events: $events, damus: damus, show_friend_icon: show_friend_icon)
            }
            .onReceive(NotificationCenter.default.publisher(for: .scroll_to_top)) { _ in
                guard let event = events.first else {
                    return
                }
                scroll_to_event(scroller: scroller, id: event.id, delay: 0.0, animate: true)
            }
        }
    }
}

/*
struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView()
    }
}
 */


struct NavigationLazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}
