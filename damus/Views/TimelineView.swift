//
//  TimelineView.swift
//  damus
//
//  Created by William Casarin on 2022-04-18.
//

import SwiftUI

struct TimelineView: View {
    @ObservedObject var events: EventHolder
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
                Color.white.opacity(0)
                    .id("startblock")
                    .frame(height: 1)
                
                InnerTimelineView(events: events, damus: damus, filter: loading ? { _ in true } : filter)
                    .redacted(reason: loading ? .placeholder : [])
                    .shimmer(loading)
                    .disabled(loading)
                    .background(GeometryReader { proxy -> Color in
                        DispatchQueue.main.async {
                            handle_scroll_queue(proxy, queue: self.events)
                        }
                        return Color.clear
                    })
            }
            .buttonStyle(BorderlessButtonStyle())
            .coordinateSpace(name: "scroll")
            .onReceive(NotificationCenter.default.publisher(for: .scroll_to_top)) { _ in
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
        TimelineView(events: events, loading: .constant(true), damus: Constants.EXAMPLE_DEMOS, show_friend_icon: true, filter: { _ in true })
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
