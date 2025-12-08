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

    /// Key for persisting scroll position. If nil, position is not saved.
    let positionKey: ScrollPositionKey?

    /// Tracks visible event IDs for position saving.
    /// Using a set because multiple events can be visible at once.
    @State private var visibleEventIds: Set<NoteId> = []

    /// Whether we've attempted to restore position on this view instance
    @State private var hasRestoredPosition = false

    init(events: EventHolder, loading: Binding<Bool>, headerHeight: Binding<CGFloat>, headerOffset: Binding<CGFloat>, damus: DamusState, show_friend_icon: Bool, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true, positionKey: ScrollPositionKey? = nil, content: (() -> Content)? = nil) {
        self.events = events
        self._loading = loading
        self._headerHeight = headerHeight
        self._headerOffset = headerOffset
        self.damus = damus
        self.show_friend_icon = show_friend_icon
        self.filter = filter
        self.apply_mute_rules = apply_mute_rules
        self.positionKey = positionKey
        self.content = content?()
    }

    init(events: EventHolder, loading: Binding<Bool>, damus: DamusState, show_friend_icon: Bool, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true, positionKey: ScrollPositionKey? = nil, content: (() -> Content)? = nil) {
        self.events = events
        self._loading = loading
        self._headerHeight = .constant(0.0)
        self._headerOffset = .constant(0.0)
        self.damus = damus
        self.show_friend_icon = show_friend_icon
        self.filter = filter
        self.apply_mute_rules = apply_mute_rules
        self.positionKey = positionKey
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

                InnerTimelineView(
                    events: events,
                    damus: damus,
                    filter: loading ? { _ in true } : filter,
                    apply_mute_rules: self.apply_mute_rules,
                    onEventVisible: { eventId in
                        visibleEventIds.insert(eventId)
                    },
                    onEventHidden: { eventId in
                        visibleEventIds.remove(eventId)
                    }
                )
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
            .disabled(self.loading)
            .onReceive(handle_notify(.scroll_to_top)) { () in
                events.flush()
                self.events.set_should_queue(false)
                scroll_to_event(scroller: scroller, id: "startblock", delay: 0.0, animate: true, anchor: .top)

                // Clear saved position when user explicitly scrolls to top
                if let key = positionKey {
                    damus.scrollPositions.clear(for: key)
                }
            }
            .onAppear {
                restoreScrollPosition(scroller: scroller)
            }
        }
        .onAppear {
            events.flush()
        }
        .onDisappear {
            saveScrollPosition()
        }
    }

    // MARK: - Scroll Position Persistence

    /// Saves the current scroll position for later restoration.
    ///
    /// We save the first visible event ID (topmost on screen).
    /// This is called when the view disappears (tab switch, navigation, background).
    private func saveScrollPosition() {
        guard let key = positionKey else { return }
        guard let firstVisible = findFirstVisibleEventId() else { return }

        damus.scrollPositions.save(eventId: firstVisible.hex(), for: key)
    }

    /// Restores scroll position from the saved state.
    ///
    /// Called once when the view appears. Uses a small delay to ensure
    /// the scroll view content is laid out before scrolling.
    private func restoreScrollPosition(scroller: ScrollViewProxy) {
        guard !hasRestoredPosition else { return }
        guard let key = positionKey else { return }
        guard let position = damus.scrollPositions.position(for: key) else { return }
        guard let noteId = NoteId(hex: position.anchorEventId) else { return }

        hasRestoredPosition = true

        // Small delay to ensure content is laid out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scroll_to_event(scroller: scroller, id: noteId, delay: 0.0, animate: false, anchor: .top)
        }
    }

    /// Finds the first (topmost) visible event ID.
    ///
    /// Since events are ordered chronologically (newest first in timeline),
    /// we need to find the one that appears first in the event list.
    private func findFirstVisibleEventId() -> NoteId? {
        guard !visibleEventIds.isEmpty else { return nil }

        // Find which visible event appears first in the filtered events list
        let filteredEvents = events.events
        for event in filteredEvents {
            if visibleEventIds.contains(event.id) {
                return event.id
            }
        }

        // Fallback: return any visible ID
        return visibleEventIds.first
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
