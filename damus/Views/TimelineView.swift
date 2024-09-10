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

    let damus: DamusState
    let show_friend_icon: Bool
    let filter: (NostrEvent) -> Bool
    let content: Content?
    let apply_mute_rules: Bool
    // Note: SceneStorage persists through a session. If user completely quits the app, scroll position is not persisted.
    @SceneStorage("scroll_position") var scroll_position: InnerTimelineView.BlockID = .top

    init(events: EventHolder, loading: Binding<Bool>, damus: DamusState, show_friend_icon: Bool, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true, content: (() -> Content)? = nil) {
        self.events = events
        self._loading = loading
        self.damus = damus
        self.show_friend_icon = show_friend_icon
        self.filter = filter
        self.apply_mute_rules = apply_mute_rules
        self.content = content?()
    }

    var body: some View {
        ScrollViewReader { scroller in
            self.MainContent(scroller: scroller)
        }
        .onAppear {
            events.flush()
        }
    }
    
    func MainContent(scroller: ScrollViewProxy) -> some View {
        if #available(iOS 17.0, *) {
            return self.MainScrollView(scroller: scroller)
                .scrollPosition(id:
                    // A custom Binding is needed to reconciliate incompatible types between this call and @SceneStorage
                    Binding(
                        get: {
                            return self.scroll_position as InnerTimelineView.BlockID?
                        },
                        set: { newValue in
                            let newValueToSet = newValue ?? .top
                            self.scroll_position = newValueToSet
                        }
                    ), anchor: .top)
        } else {
            return self.MainScrollView(scroller: scroller)
        }
    }
    
    func MainScrollView(scroller: ScrollViewProxy) -> some View {
        ScrollView {
            if let content {
                content
            }
            
            Color.white.opacity(0)
                .id(InnerTimelineView.BlockID.top)
                .frame(height: 1)
            
            InnerTimelineView(events: events, damus: damus, filter: loading ? { _ in true } : filter, apply_mute_rules: self.apply_mute_rules)
                .redacted(reason: loading ? .placeholder : [])
                .shimmer(loading)
                .disabled(loading)
                .background(GeometryReader { proxy -> Color in
                    handle_scroll_queue(proxy, queue: self.events)
                    return Color.clear
                })
        }
        .coordinateSpace(name: "scroll")
        .onReceive(handle_notify(.scroll_to_top)) { () in
            events.flush()
            self.events.should_queue = false
            withAnimation {
                self.scroll_position = .top
            }
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
