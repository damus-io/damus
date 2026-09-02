//
//  TimelineView.swift
//  damus
//
//  Created by William Casarin on 2022-04-18.
//

import SwiftUI

struct TimelineView<Content: View>: View {
    @ObservedObject var events: EventHolder
    @Binding var loading: Bool
    @Binding var headerHeight: CGFloat
    /// Drives the header's hide/reveal. Held unobserved on purpose: this view writes it on
    /// every scroll frame, and observing it here would rebuild the whole timeline per frame.
    let headerOffset: HeaderOffsetModel?

    let damus: DamusState
    let show_friend_icon: Bool
    let filter: (NostrEvent) -> Bool
    let content: Content?
    let apply_mute_rules: Bool
    let viewId: AnyHashable?

    init(events: EventHolder, loading: Binding<Bool>, headerHeight: Binding<CGFloat>, headerOffset: HeaderOffsetModel, damus: DamusState, show_friend_icon: Bool, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true, viewId: AnyHashable? = nil, content: (() -> Content)? = nil) {
        self.events = events
        self._loading = loading
        self._headerHeight = headerHeight
        self.headerOffset = headerOffset
        self.damus = damus
        self.show_friend_icon = show_friend_icon
        self.filter = filter
        self.apply_mute_rules = apply_mute_rules
        self.viewId = viewId
        self.content = content?()
    }
    
    init(events: EventHolder, loading: Binding<Bool>, damus: DamusState, show_friend_icon: Bool, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true, viewId: AnyHashable? = nil, content: (() -> Content)? = nil) {
        self.events = events
        self._loading = loading
        self._headerHeight = .constant(0.0)
        self.headerOffset = nil
        self.damus = damus
        self.show_friend_icon = show_friend_icon
        self.filter = filter
        self.apply_mute_rules = apply_mute_rules
        self.viewId = viewId
        self.content = content?()
    }

    var body: some View {
        MainContent
    }
    
    var topPadding: CGFloat {
        if #available(iOS 26.0, *) {
            headerHeight
        }
        else {
            headerHeight - getSafeAreaTop()
        }
    }
    
    var MainContent: some View {
        ScrollViewReader { scroller in
            ScrollView {
                if let content {
                    content
                }

                Color.clear
                    .id("startblock")
                    .frame(height: 0)

                InnerTimelineView(events: events, damus: damus, filter: loading ? { _ in true } : filter, apply_mute_rules: self.apply_mute_rules)
                    .id(viewId)
                    .redacted(reason: loading ? .placeholder : [])
                    .shimmer(loading)
                    .disabled(loading)
                    .padding(.top, topPadding)
                    .offsetY { previous, current in
                        // No header to move: this timeline has no chrome bound to the scroll.
                        guard let header = headerOffset else { return }

                        if previous > current{
                            if header.direction != .up && current < 0 {
                                header.shiftOffset = current - header.offset
                                header.direction = .up
                                header.lastOffset = header.offset
                            }

                            let offset = current < 0 ? (current - header.shiftOffset) : 0
                            header.offset = (-offset < headerHeight ? (offset < 0 ? offset : 0) : -headerHeight)
                        }else {
                            if header.direction != .down {
                                header.shiftOffset = current
                                header.direction = .down
                                header.lastOffset = header.offset
                            }

                            let offset = header.lastOffset + (current - header.shiftOffset)
                            header.offset = (offset > 0 ? 0 : offset)
                        }
                    }
                    .background {
                        GeometryReader { proxy -> Color in
                            handle_scroll_queue(proxy, queue: self.events)
                            return Color.clear
                        }
                    }
            }
            .coordinateSpace(name: "scroll")
            .disabled(self.loading)
            .onReceive(handle_notify(.scroll_to_top)) { () in
                events.flush()
                self.events.set_should_queue(false)
                scroll_to_event(scroller: scroller, id: "startblock", delay: 0.0, animate: true, anchor: .top)
            }
        }
        .onAppear {
            events.flush()
        }
    }
}

struct TimelineView_Previews: PreviewProvider {
    @StateObject static var events = test_event_holder
    static var previews: some View {
        TimelineView<AnyView>(events: events, loading: .constant(true), damus: test_damus_state, show_friend_icon: true, filter: { _ in true })
    }
}


protocol ScrollQueue {
    var should_queue: Bool { get }
    func set_should_queue(_ val: Bool)
}
    
func handle_scroll_queue(_ proxy: GeometryProxy, queue: ScrollQueue) {
    let offset = -proxy.frame(in: .named("scroll")).origin.y
    let new_should_queue = offset > 0
    if queue.should_queue != new_should_queue {
        queue.set_should_queue(new_should_queue)
    }
}
