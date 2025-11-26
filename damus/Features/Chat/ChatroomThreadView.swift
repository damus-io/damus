//
//  ChatroomView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI
import SwipeActions
import TipKit

struct ChatroomThreadView: View {
    @Environment(\.dismiss) var dismiss
    @State var once: Bool = false
    let damus: DamusState
    @ObservedObject var thread: ThreadModel
    @State var highlighted_note_id: NoteId? = nil
    @State var user_just_posted_flag: Bool = false
    @State var untrusted_network_expanded: Bool = true
    @Namespace private var animation

    // Add state for sticky header
    @State var showStickyHeader: Bool = false
    @State var untrustedSectionOffset: CGFloat = 0

    private static let untrusted_network_section_id = "untrusted-network-section"
    private static let sticky_header_adjusted_anchor = UnitPoint(x: UnitPoint.top.x, y: 0.2)

    func go_to_event(scroller: ScrollViewProxy, note_id: NoteId) {
        let adjustedAnchor: UnitPoint = showStickyHeader ? ChatroomThreadView.sticky_header_adjusted_anchor : .top

        scroll_to_event(scroller: scroller, id: note_id, delay: 0, animate: true, anchor: adjustedAnchor)
        highlighted_note_id = note_id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            withAnimation {
                highlighted_note_id = nil
            }
        })
    }

    func set_active_event(scroller: ScrollViewProxy, ev: NdbNote) {
        withAnimation {
            self.thread.select(event: ev)
            self.go_to_event(scroller: scroller, note_id: ev.id)
        }
    }

    func trusted_event_filter(_ event: NostrEvent) -> Bool {
        !damus.settings.show_trusted_replies_first || damus.contacts.is_in_friendosphere(event.pubkey)
    }

    func ThreadedSwipeViewGroup(scroller: ScrollViewProxy, events: [NostrEvent]) -> some View {
        SwipeViewGroup {
            ForEach(Array(zip(events, events.indices)), id: \.0.id) { (ev, ind) in
                ChatEventView(event: events[ind],
                              selected_event: self.thread.selected_event,
                              prev_ev: ind > 0 ? events[ind-1] : nil,
                              next_ev: ind == events.count-1 ? nil : events[ind+1],
                              damus_state: damus,
                              thread: thread,
                              scroll_to_event: { note_id in
                    self.go_to_event(scroller: scroller, note_id: note_id)
                },
                              focus_event: {
                    self.set_active_event(scroller: scroller, ev: ev)
                },
                              highlight_bubble: highlighted_note_id == ev.id
                )
                .id(ev.id)
                .matchedGeometryEffect(id: ev.id.hex(), in: animation, anchor: .center)
                .padding(.horizontal)
            }
        }
    }

    var OutsideTrustedNetworkLabel: some View {
        HStack {
            Label(
                NSLocalizedString(
                    "Replies outside your trusted network",
                    comment: "Section title in thread for replies from outside of the current user's trusted network, which is their follows and follows of follows."),
                systemImage: "network.slash"
            )
            Spacer()
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(untrusted_network_expanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.1), value: untrusted_network_expanded)
        }
        .foregroundColor(.secondary)
    }

    var StickyHeaderView: some View {
        OutsideTrustedNetworkLabel
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(
                Color(UIColor.systemBackground)
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
            )
    }

    var body: some View {
        ScrollViewReader { scroller in
            let sorted_child_events = thread.sorted_child_events

            let untrusted_events = sorted_child_events.filter { !trusted_event_filter($0) }
            let trusted_events = sorted_child_events.filter { trusted_event_filter($0) }

            ZStack(alignment: .top) {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // MARK: - Parents events view
                        ForEach(thread.parent_events, id: \.id) { parent_event in
                            EventMutingContainerView(damus_state: damus, event: parent_event) {
                                EventView(damus: damus, event: parent_event)
                                    .matchedGeometryEffect(id: parent_event.id.hex(), in: animation, anchor: .center)
                            }
                            .padding(.horizontal)
                            .onTapGesture {
                                self.set_active_event(scroller: scroller, ev: parent_event)
                            }
                            .id(parent_event.id)

                            Divider()
                                .padding(.top, 4)
                                .padding(.leading, 25 * 2)

                        }.background(GeometryReader { geometry in
                            let eventHeight = geometry.frame(in: .global).height

                            Rectangle()
                                .fill(Color.gray.opacity(0.25))
                                .frame(width: 2, height: eventHeight)
                                .offset(x: 40, y: 40)
                        })

                        // MARK: - Actual event view
                        EventMutingContainerView(
                            damus_state: damus,
                            event: self.thread.selected_event,
                            muteBox: { event_shown, muted_reason in
                                AnyView(
                                    EventMutedBoxView(shown: event_shown, reason: muted_reason)
                                        .padding(5)
                                )
                            }
                        ) {
                            SelectedEventView(damus: damus, event: self.thread.selected_event, size: .selected)
                                .matchedGeometryEffect(id: self.thread.selected_event.id.hex(), in: animation, anchor: .center)
                        }
                        .id(self.thread.selected_event.id)

                        // MARK: - Children view - inside trusted network
                        if !trusted_events.isEmpty {
                            ThreadedSwipeViewGroup(scroller: scroller, events: trusted_events)
                        }
                    }
                    .padding(.top)

                    // MARK: - Children view - outside trusted network
                    if !untrusted_events.isEmpty {
                        if #available(iOS 17, *) {
                            TipView(TrustedNetworkRepliesTip.shared, arrowEdge: .bottom)
                                .padding(.top, 10)
                                .padding(.horizontal)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            // Track this section's position
                            Color.clear
                                .frame(height: 1)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .onAppear {
                                                untrustedSectionOffset = proxy.frame(in: .global).minY
                                            }
                                            .onChange(of: proxy.frame(in: .global).minY) { newY in
                                                let shouldShow = newY <= 100 // Adjust this threshold as needed
                                                if shouldShow != showStickyHeader {
                                                    withAnimation(.easeInOut(duration: 0.3)) {
                                                        showStickyHeader = shouldShow
                                                    }
                                                }
                                            }
                                    }
                                )

                            Button(action: {
                                withAnimation {
                                    untrusted_network_expanded.toggle()

                                    if #available(iOS 17, *) {
                                        TrustedNetworkRepliesTip.shared.invalidate(reason: .actionPerformed)
                                    }

                                    scroll_to_event(scroller: scroller, id: ChatroomThreadView.untrusted_network_section_id, delay: 0.1, animate: true, anchor: ChatroomThreadView.sticky_header_adjusted_anchor)
                                }
                            }) {
                                OutsideTrustedNetworkLabel
                            }
                            .id(ChatroomThreadView.untrusted_network_section_id)
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal)

                            if untrusted_network_expanded {
                                withAnimation {
                                    LazyVStack(alignment: .leading, spacing: 8) {
                                        ThreadedSwipeViewGroup(scroller: scroller, events: untrusted_events)
                                    }
                                    .padding(.top, 10)
                                }
                            }
                        }
                    }

                    EndBlock()

                    HStack {}
                        .frame(height: tabHeight + getSafeAreaBottom())
                }

                if showStickyHeader && !untrusted_events.isEmpty {
                    VStack {
                        StickyHeaderView
                            .onTapGesture {
                                withAnimation {
                                    untrusted_network_expanded.toggle()
                                }
                            }
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .onReceive(handle_notify(.post), perform: { notify in
                switch notify {
                case .post(_):
                    user_just_posted_flag = true
                case .cancel:
                    return
                }
            })
            .onReceive(thread.objectWillChange) {
                if let last_event = thread.events.last, last_event.pubkey == damus.pubkey, user_just_posted_flag {
                    self.go_to_event(scroller: scroller, note_id: last_event.id)
                    user_just_posted_flag = false
                }
            }
            .onAppear() {
                thread.subscribe()
                scroll_to_event(scroller: scroller, id: thread.selected_event.id, delay: 0.1, animate: false)
            }
            .onDisappear() {
                thread.unsubscribe()
            }
        }
    }
}

struct ChatroomView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChatroomThreadView(damus: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state))
                .previewDisplayName("Test note")
            
            let test_thread = ThreadModel(event: test_thread_note_1, damus_state: test_damus_state)
            ChatroomThreadView(damus: test_damus_state, thread: test_thread)
                .onAppear {
                    test_thread.add_event(test_thread_note_2, keypair: test_keypair)
                    test_thread.add_event(test_thread_note_3, keypair: test_keypair)
                    test_thread.add_event(test_thread_note_4, keypair: test_keypair)
                    test_thread.add_event(test_thread_note_5, keypair: test_keypair)
                    test_thread.add_event(test_thread_note_6, keypair: test_keypair)
                    test_thread.add_event(test_thread_note_7, keypair: test_keypair)
                }
        }
    }
}
