//
//  ThreadV2View.swift
//  damus
//
//  Created by Thomas Tastet on 25/12/2022.
//

import SwiftUI

struct ThreadView: View {
    let state: DamusState
    
    @ObservedObject var thread: ThreadModel
    @Environment(\.dismiss) var dismiss
    
    var parent_events: [NostrEvent] {
        state.events.parent_events(event: thread.event, keypair: state.keypair)
    }
    
    var sorted_child_events: [NostrEvent] {
        state.events.child_events(event: thread.event).sorted(by: { a, b in
            let a_is_muted = !should_show_event(event: a, damus_state: state)
            let b_is_muted = !should_show_event(event: b, damus_state: state)
            
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
    
    var body: some View {
        //let top_zap = get_top_zap(events: state.events, evid: thread.event.id)
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack {
                    // MARK: - Parents events view
                    ForEach(parent_events, id: \.id) { parent_event in
                        EventMutingContainerView(damus_state: state, event: parent_event) {
                            EventView(damus: state, event: parent_event)
                        }
                        .padding(.horizontal)
                        .onTapGesture {
                            thread.set_active_event(parent_event, keypair: self.state.keypair)
                            scroll_to_event(scroller: reader, id: parent_event.id, delay: 0.1, animate: false)
                        }
                        
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
                        damus_state: state,
                        event: self.thread.event,
                        muteBox: { event_shown in
                            AnyView(
                                EventMutedBoxView(shown: event_shown)
                                .padding(5)
                            )
                        }
                    ) {
                        SelectedEventView(damus: state, event: self.thread.event, size: .selected)
                    }
                    .id(self.thread.event.id)
                    
                    /*
                    if let top_zap {
                        ZapEvent(damus: state, zap: top_zap, is_top_zap: true)
                            .padding(.horizontal)
                    }
                     */
                    
                    ForEach(sorted_child_events, id: \.id) { child_event in
                        EventMutingContainerView(
                            damus_state: state,
                            event: child_event
                        ) {
                            EventView(damus: state, event: child_event)
                        }
                        .padding(.horizontal)
                        .onTapGesture {
                            thread.set_active_event(child_event, keypair: state.keypair)
                            scroll_to_event(scroller: reader, id: child_event.id, delay: 0.1, animate: false)
                        }
                        
                        Divider()
                            .padding([.top], 4)
                    }
                }
            }.navigationBarTitle(NSLocalizedString("Thread", comment: "Navigation bar title for note thread."))
            .onAppear {
                thread.subscribe()
                let anchor: UnitPoint = self.thread.event.known_kind == .longform ? .top : .bottom
                scroll_to_event(scroller: reader, id: self.thread.event.id, delay: 0.0, animate: false, anchor: anchor)
            }
            .onDisappear {
                thread.unsubscribe()
            }
            .onReceive(handle_notify(.switched_timeline)) { notif in
                dismiss()
            }
        }
    }
}

struct ThreadView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        let thread = ThreadModel(event: test_note, damus_state: state)
        ThreadView(state: state, thread: thread)
    }
}
