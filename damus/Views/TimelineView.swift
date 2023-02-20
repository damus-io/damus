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

struct TimelineView: View {
    @ObservedObject var events: EventHolder
    @Binding var loading: Bool
    @State var offset = CGFloat.zero
    
    @Environment(\.colorScheme) var colorScheme

    let damus: DamusState
    let show_friend_icon: Bool
    let filter: (NostrEvent) -> Bool
    
    var body: some View {
        MainContent
    }
    
    func handle_scroll(_ proxy: GeometryProxy) {
        let offset = -proxy.frame(in: .named("scroll")).origin.y
        guard offset != -0.0 else {
            return
        }
        self.events.should_queue = offset > 0
    }
    
    var realtime_bar_opacity: Double {
        colorScheme == .dark ? 0.2 : 0.1
    }
    
    var MainContent: some View {
        ScrollViewReader { scroller in
            ScrollView {
                InnerTimelineView(events: events, damus: damus, show_friend_icon: show_friend_icon, filter: loading ? { _ in true } : filter)
                    .redacted(reason: loading ? .placeholder : [])
                    .shimmer(loading)
                    .disabled(loading)
                    .background(GeometryReader { proxy -> Color in
                        DispatchQueue.main.async {
                            handle_scroll(proxy)
                        }
                        return Color.clear
                    })
            }
            .overlay(
                Rectangle()
                    .fill(RECTANGLE_GRADIENT.opacity(realtime_bar_opacity))
                    .offset(y: -1)
                    .frame(height: events.should_queue ? 0 : 8)
                    ,
                alignment: .top
            )
            .buttonStyle(BorderlessButtonStyle())
            .coordinateSpace(name: "scroll")
            .onReceive(NotificationCenter.default.publisher(for: .scroll_to_top)) { _ in
                guard let event = events.events.filter(self.filter).first else {
                    return
                }
                events.flush()
                scroll_to_event(scroller: scroller, id: event.id, delay: 0.0, animate: true, anchor: .top)
            }
        }
    }
}

struct TimelineView_Previews: PreviewProvider {
    @StateObject static var events = test_event_holder
    static var previews: some View {
        TimelineView(events: events, loading: .constant(true), damus: Constants.EXAMPLE_DEMOS, show_friend_icon: true, filter: { _ in true })
    }
}


