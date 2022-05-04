//
//  ChatroomView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI

struct ChatroomView: View {
    @EnvironmentObject var thread: ThreadModel
    @Environment(\.dismiss) var dismiss
    let likes: EventCounter
    let our_pubkey: String
    
    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading) {
                    let count = thread.events.count
                    ForEach(Array(zip(thread.events, thread.events.indices)), id: \.0.id) { (ev, ind) in
                        ChatView(event: thread.events[ind],
                                 prev_ev: ind > 0 ? thread.events[ind-1] : nil,
                                 next_ev: ind == count-1 ? nil : thread.events[ind+1],
                                 likes: likes,
                                 our_pubkey: our_pubkey
                        )
                        .onTapGesture {
                            if thread.event.id == ev.id {
                                //dismiss()
                                toggle_thread_view()
                            } else {
                                thread.set_active_event(ev)
                            }
                        }
                        .environmentObject(thread)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .select_quote)) { notif in
                let ev = notif.object as! NostrEvent
                if ev.id != thread.event.id {
                    thread.set_active_event(ev)
                }
                scroll_to_event(scroller: scroller, id: ev.id, delay: 0, animate: true, anchor: .top)
            }
            .onAppear() {
                scroll_to_event(scroller: scroller, id: thread.event.id, delay: 0.3, animate: true, anchor: .bottom)
            }
        }
    }
    
    func toggle_thread_view() {
        NotificationCenter.default.post(name: .toggle_thread_view, object: nil)
    }
}




/*
struct ChatroomView_Previews: PreviewProvider {
    @State var events = [NostrEvent(content: "hello", pubkey: "pubkey")]
    
    static var previews: some View {
        ChatroomView(events: events)
    }
}
 */
