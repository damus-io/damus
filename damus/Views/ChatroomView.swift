//
//  ChatroomView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI

struct ChatroomView: View {
    @Environment(\.dismiss) var dismiss
    @State var once: Bool = false
    let damus: DamusState
    @ObservedObject var thread: ThreadModel
    @State var selected_note_id: NoteId? = nil
    @State var user_just_posted_flag: Bool = false
    @Namespace private var animation
    
    var parent_events: [NostrEvent] {
        damus.events.parent_events(event: thread.event, keypair: damus.keypair)
    }
    
    var sorted_child_events: [NostrEvent] {
        let all_recursive_child_events = self.recursive_child_events(event: thread.event)
        return all_recursive_child_events.sorted(by: { a, b in
            let a_is_muted = !should_show_event(event: a, damus_state: damus)
            let b_is_muted = !should_show_event(event: b, damus_state: damus)
            
            if a_is_muted == b_is_muted {
                // If both are muted or unmuted, sort them based on their creation date.
                return a.created_at < b.created_at
            }
            else {
                // Muting status is different
                // Prioritize the replies that are not muted
                return !a_is_muted && b_is_muted
            }
        })
    }
    
    func recursive_child_events(event: NdbNote) -> [NdbNote] {
        let immediate_children = damus.events.child_events(event: event)
        var indirect_children: [NdbNote] = []
        for immediate_child in immediate_children {
            indirect_children.append(contentsOf: self.recursive_child_events(event: immediate_child))
        }
        return immediate_children + indirect_children
    }
    
    func go_to_event(scroller: ScrollViewProxy, note_id: NoteId) {
        scroll_to_event(scroller: scroller, id: note_id, delay: 0, animate: true, anchor: .top)
        selected_note_id = note_id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            withAnimation {
                selected_note_id = nil
            }
        })
    }
    
    func set_active_event(scroller: ScrollViewProxy, ev: NdbNote) {
        withAnimation {
            thread.set_active_event(ev, keypair: self.damus.keypair)
            self.go_to_event(scroller: scroller, note_id: ev.id)
        }
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // MARK: - Parents events view
                    ForEach(parent_events, id: \.id) { parent_event in
                        EventMutingContainerView(damus_state: damus, event: parent_event) {
                            EventView(damus: damus, event: parent_event)
                        }
                        .padding(.horizontal)
                        .onTapGesture {
                            self.set_active_event(scroller: scroller, ev: parent_event)
                        }
                        .id(parent_event.id)
                        .matchedGeometryEffect(id: parent_event.id.hex(), in: animation)
                        
                        Divider()
                            .padding(.top, 4)
                            .padding(.leading, 25 * 2)
                        
                    }.background(GeometryReader { geometry in
                        // get the height and width of the EventView view
                        let eventHeight = geometry.frame(in: .global).height
                        //                    let eventWidth = geometry.frame(in: .global).width
                        
                        // vertical gray line in the background
                        Rectangle()
                            .fill(Color.gray.opacity(0.25))
                            .frame(width: 2, height: eventHeight)
                            .offset(x: 40, y: 40)
                    })
                    
                    // MARK: - Actual event view
                    EventMutingContainerView(
                        damus_state: damus,
                        event: self.thread.event,
                        muteBox: { event_shown, muted_reason in
                            AnyView(
                                EventMutedBoxView(shown: event_shown, reason: muted_reason)
                                .padding(5)
                            )
                        }
                    ) {
                        SelectedEventView(damus: damus, event: self.thread.event, size: .selected)
                    }
                    .id(self.thread.event.id)
                    .matchedGeometryEffect(id: self.thread.event.id.hex(), in: animation)
                    
                    // MARK: - Children view
                    let events = sorted_child_events
                    let count = events.count
                    ForEach(Array(zip(events, events.indices)), id: \.0.id) { (ev, ind) in
                        EventMutingContainerView(
                            damus_state: damus,
                            event: ev,
                            muteBox: { event_shown, muted_reason in
                                AnyView(
                                    EventMutedBoxView(shown: event_shown, reason: muted_reason)
                                        .padding(5)
                                )
                            }) {
                                ChatView(event: events[ind],
                                         selected_event: self.thread.event,
                                         prev_ev: ind > 0 ? events[ind-1] : nil,
                                         next_ev: ind == count-1 ? nil : events[ind+1],
                                         damus_state: damus,
                                         thread: thread,
                                         scroll_to_event: { note_id in
                                    self.go_to_event(scroller: scroller, note_id: note_id)
                                },
                                         focus_event: {
                                    self.set_active_event(scroller: scroller, ev: ev)
                                },
                                         highlight_bubble: selected_note_id == ev.id
                                )
                                .padding(.horizontal)
                        }
                        .id(ev.id)
                        .matchedGeometryEffect(id: ev.id.hex(), in: animation)
                    }
                }
                .padding(.top)
                EndBlock()
            }
            /*
            .onReceive(NotificationCenter.default.publisher(for: .select_quote)) { notif in
                let ev = notif.object as! NostrEvent
                if ev.id != thread.event.id {
                    thread.set_active_event(ev, privkey: damus.keypair.privkey)
                }
                scroll_to_event(scroller: scroller, id: ev.id, delay: 0, animate: true)
            }
            .onChange(of: thread.loading) { _ in
                guard !thread.loading && !once else {
                    return
                }
                scroll_after_load(thread: thread, proxy: scroller)
                once = true
            }
             */
            .onReceive(handle_notify(.post), perform: { notify in
                switch notify {
                    case .post(_):
                        user_just_posted_flag = true
                    case .cancel:
                        return
                }
            })
            .onReceive(thread.objectWillChange) {
                if let last_event = thread.events().last, last_event.pubkey == damus.pubkey, user_just_posted_flag {
                    self.go_to_event(scroller: scroller, note_id: last_event.id)
                    user_just_posted_flag = false
                }
            }
            .onAppear() {
                thread.subscribe()
                scroll_to_event(scroller: scroller, id: thread.event.id, delay: 0.1, animate: false)
            }
            .onDisappear() {
                thread.unsubscribe()
            }
        }
    }

    func toggle_thread_view() {
        NotificationCenter.default.post(name: .toggle_thread_view, object: nil)
    }
}




struct ChatroomView_Previews: PreviewProvider {
    static var previews: some View {
        ChatroomView(damus: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state))
    }
}

func scroll_after_load(thread: ThreadModel, proxy: ScrollViewProxy) {
    scroll_to_event(scroller: proxy, id: thread.event.id, delay: 0.1, animate: false)
}
