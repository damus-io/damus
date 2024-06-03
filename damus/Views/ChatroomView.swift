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
    
    func go_to_event(scroller: ScrollViewProxy, note_id: NoteId) {
        scroll_to_event(scroller: scroller, id: note_id, delay: 0, animate: true)
        selected_note_id = note_id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            withAnimation {
                selected_note_id = nil
            }
        })
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    let events = thread.events()
                    let count = events.count
                    ForEach(Array(zip(events, events.indices)), id: \.0.id) { (ev, ind) in
                        if(thread.original_event.id == ev.id) {
                            SelectedEventView(damus: damus, event: ev, size: .selected)
                        }
                        else {
                            ChatView(event: events[ind],
                                     prev_ev: ind > 0 ? events[ind-1] : nil,
                                     next_ev: ind == count-1 ? nil : events[ind+1],
                                     damus_state: damus,
                                     thread: thread,
                                     scroll_to_event: { note_id in
                                self.go_to_event(scroller: scroller, note_id: note_id)
                            },
                                     highlight_bubble: selected_note_id == ev.id
                            )
                            .padding(.horizontal)
                            
                        }
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
            .onReceive(thread.objectWillChange) {
                if let last_event = thread.events().last, last_event.pubkey == damus.pubkey {
                    self.go_to_event(scroller: scroller, note_id: last_event.id)
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
