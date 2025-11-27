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
        ZStack(alignment: .top) {
            ScrollViewReader { scroller in
                ScrollView {
                    if let content {
                        content
                    }

                    Color.clear
                        .id("startblock")
                        .frame(height: 0)

                    if loading {
                        TimelineSkeletonList()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .padding(.top, topPadding)
                    }

                    InnerTimelineView(events: events, damus: damus, filter: filter, apply_mute_rules: self.apply_mute_rules)
                        .padding(.top, loading ? 0 : topPadding)
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
                    self.events.set_should_queue(false)
                    scroll_to_event(scroller: scroller, id: "startblock", delay: 0.0, animate: true, anchor: .top)
                }
            }

            if loading {
                TimelineLoadingBanner()
                    .padding(.top, topPadding + 8)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: loading)
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

struct TimelineSkeletonList: View {
    private let rowCount = 4
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                TimelineSkeletonRow()
                if index != rowCount - 1 {
                    ThiccDivider()
                        .padding(.top, 7)
                }
            }
        }
        .shimmer(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Loading new notes", comment: "Accessibility label for the timeline skeleton rows that indicate the feed is refreshing."))
    }
}

struct TimelineSkeletonRow: View {
    private var avatarColor: Color {
        DamusColors.adaptableGrey.opacity(0.45)
    }
    
    private var lineColor: Color {
        DamusColors.adaptableGrey.opacity(0.35)
    }
    
    private var pillColor: Color {
        DamusColors.adaptableGrey.opacity(0.28)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(avatarColor)
                    .frame(width: 44, height: 44)
                
                VStack(alignment: .leading, spacing: 10) {
                    skeletonLine(width: 120, height: 12)
                        .opacity(0.8)
                    
                    skeletonLine(width: 220)
                    skeletonLine(width: 180)
                    skeletonLine(width: 140)
                }
            }
            
            HStack(spacing: 16) {
                pill(width: 50)
                pill(width: 36)
                pill(width: 44)
                pill(width: 32)
            }
        }
        .padding(.top, 7)
    }
    
    private func skeletonLine(width: CGFloat, height: CGFloat = 10) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(lineColor)
                .frame(width: width, height: height)
            Spacer(minLength: 0)
        }
    }
    
    private func pill(width: CGFloat) -> some View {
        Capsule()
            .fill(pillColor)
            .frame(width: width, height: 10)
    }
}

struct TimelineLoadingBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: DamusColors.purple))
                .scaleEffect(0.85)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("Connecting to relays...", comment: "Primary status text shown while the timeline waits for relays to send fresh notes."))
                    .font(.footnote)
                    .fontWeight(.semibold)
                Text(NSLocalizedString("Showing cached notes while we sync.", comment: "Secondary status text shown while the timeline is still loading new notes from relays."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DamusColors.highlight.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DamusColors.highlight.opacity(0.25))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(NSLocalizedString("We will refresh as soon as relays respond.", comment: "Accessibility hint describing that the app is still loading new notes from relays."))
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
