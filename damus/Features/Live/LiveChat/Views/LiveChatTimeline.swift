//
//  LiveChatTimeline.swift
//  damus
//
//  Created by eric on 8/7/25.
//

import SwiftUI

struct LiveChatTimelineView<Content: View>: View {
    @ObservedObject var events: EventHolder
    @Binding var loading: Bool

    let damus: DamusState
    let show_friend_icon: Bool
    let filter: (NostrEvent) -> Bool
    let content: Content?
    let apply_mute_rules: Bool

    init(events: EventHolder, loading: Binding<Bool>, headerHeight: Binding<CGFloat>, headerOffset: Binding<CGFloat>, damus: DamusState, show_friend_icon: Bool, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true, content: (() -> Content)? = nil) {
        self.events = events
        self._loading = loading
        self.damus = damus
        self.show_friend_icon = show_friend_icon
        self.filter = filter
        self.apply_mute_rules = apply_mute_rules
        self.content = content?()
    }

    init(events: EventHolder, loading: Binding<Bool>, damus: DamusState, show_friend_icon: Bool, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true, content: (() -> Content)? = nil) {
        self.events = events
        self._loading = loading
        self.damus = damus
        self.show_friend_icon = show_friend_icon
        self.filter = filter
        self.apply_mute_rules = apply_mute_rules
        self.content = content?()
    }

    func scroll_to_end(_ scroller: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation {
                scroller.scrollTo("endblock")
            }
        } else {
            scroller.scrollTo("endblock")
        }
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                if let content {
                    content
                }

                Color.clear
                    .id("startblock")
                    .frame(height: 0)

                LiveChatInnerView(events: events, damus: damus, filter: loading ? { _ in true } : filter, apply_mute_rules: self.apply_mute_rules)
                    .redacted(reason: loading ? .placeholder : [])
                    .shimmer(loading)
                    .disabled(loading)
                    .background {
                        GeometryReader { proxy -> Color in
                            handle_scroll_queue(proxy, queue: self.events)
                            return Color.clear
                        }
                    }
            }
            .coordinateSpace(name: "scroll")
            .onReceive(handle_notify(.scroll_to_top)) { () in
                events.flush()
                self.events.should_queue = false
                scroll_to_event(scroller: scroller, id: "startblock", delay: 0.0, animate: true, anchor: .top)
            }
        }
        .onAppear {
            events.flush()
        }
    }
}

struct LiveChatInnerView: View {
    @ObservedObject var events: EventHolder
    let state: DamusState
    let filter: (NostrEvent) -> Bool

    init(events: EventHolder, damus: DamusState, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true) {
        self.events = events
        self.state = damus
        self.filter = apply_mute_rules ? { filter($0) && !damus.mutelist_manager.is_event_muted($0) } : filter
    }

    var event_options: EventViewOptions {
        if self.state.settings.truncate_timeline_text {
            return [.wide, .truncate_content]
        }

        return [.wide]
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            let events = self.events.events
            if events.isEmpty {
                EmptyTimelineView()
            } else {
                let evs = events.filter(filter)
                let indexed = Array(zip(evs, 0...))
                ForEach(indexed, id: \.0.id) { tup in
                    let ev = tup.0
                    let ind = tup.1
                    if ev.kind == NostrKind.live_chat.rawValue {
                        LiveChatView(state: state, ev: ev)
                            .padding(.top, 7)
                            .onAppear {
                                let to_preload =
                                Array([indexed[safe: ind+1]?.0,
                                       indexed[safe: ind+2]?.0,
                                       indexed[safe: ind+3]?.0,
                                       indexed[safe: ind+4]?.0,
                                       indexed[safe: ind+5]?.0
                                      ].compactMap({ $0 }))

                                preload_events(state: state, events: to_preload)
                            }
                    }
                }
            }
        }
        .padding(.bottom)

    }
}
