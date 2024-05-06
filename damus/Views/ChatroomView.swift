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

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading) {
                    let events = thread.events()
                    let count = events.count
                    ForEach(Array(zip(events, events.indices)), id: \.0.id) { (ev, ind) in
                        ChatView(event: events[ind],
                                 prev_ev: ind > 0 ? events[ind-1] : nil,
                                 next_ev: ind == count-1 ? nil : events[ind+1],
                                 damus_state: damus,
                                 thread: thread
                        )
                        /*
                        .contextMenu{MenuItems(event: ev, keypair: damus.keypair, target_pubkey: ev.pubkey, profileModel: ProfileModel(pubkey: ev.pubkey, damus: damus))}
                         */
                        .onTapGesture {
                            if thread.event.id == ev.id {
                                //dismiss()
                                toggle_thread_view()
                            } else {
                                //thread.set_active_event(ev, privkey: damus.keypair.privkey)
                            }
                        }
                    }
                    
                }
                .padding(.horizontal)
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
