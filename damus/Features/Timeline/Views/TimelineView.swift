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
    @Binding var headerOffset: CGFloat
    @State var shiftOffset: CGFloat = 0
    @State var lastHeaderOffset: CGFloat = 0
    @State var direction: SwipeDirection = .none

    let damus: DamusState
    let show_friend_icon: Bool
    let filter: (NostrEvent) -> Bool
    let content: Content?
    let apply_mute_rules: Bool

    init(events: EventHolder, loading: Binding<Bool>, headerHeight: Binding<CGFloat>, headerOffset: Binding<CGFloat>, damus: DamusState, show_friend_icon: Bool, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true, content: (() -> Content)? = nil) {
        self.events = events
        self._loading = loading
        self._headerHeight = headerHeight
        self._headerOffset = headerOffset
        self.damus = damus
        self.show_friend_icon = show_friend_icon
        self.filter = filter
        self.apply_mute_rules = apply_mute_rules
        self.content = content?()
    }
    
    init(events: EventHolder, loading: Binding<Bool>, damus: DamusState, show_friend_icon: Bool, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true, content: (() -> Content)? = nil) {
        self.events = events
        self._loading = loading
        self._headerHeight = .constant(0.0)
        self._headerOffset = .constant(0.0)
        self.damus = damus
        self.show_friend_icon = show_friend_icon
        self.filter = filter
        self.apply_mute_rules = apply_mute_rules
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

                InnerTimelineView(events: events, damus: damus, filter: filter, apply_mute_rules: self.apply_mute_rules)
                    .redacted(reason: loading ? .placeholder : [])
                    .shimmer(loading)
                    .disabled(loading)
                    .padding(.top, topPadding)
                    .offsetY { previous, current in
                        if previous > current{
                            if direction != .up && current < 0 {
                                shiftOffset = current - headerOffset
                                direction = .up
                                lastHeaderOffset = headerOffset
                            }
                            
                            let offset = current < 0 ? (current - shiftOffset) : 0
                            headerOffset = (-offset < headerHeight ? (offset < 0 ? offset : 0) : -headerHeight)
                        }else {
                            if direction != .down {
                                shiftOffset = current
                                direction = .down
                                lastHeaderOffset = headerOffset
                            }
                            
                            let offset = lastHeaderOffset + (current - shiftOffset)
                            headerOffset = (offset > 0 ? 0 : offset)
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
    guard offset >= 0 else {
        return
    }
    let val = offset > 0
    if queue.should_queue != val {
        queue.set_should_queue(val)
    }
}
