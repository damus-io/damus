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
    @State var once: Bool = false
    let damus: DamusState
    
    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(alignment: .leading) {
                    let count = thread.events.count
                    ForEach(Array(zip(thread.events, thread.events.indices)), id: \.0.id) { (ev, ind) in
                        ChatView(event: thread.events[ind],
                                 prev_ev: ind > 0 ? thread.events[ind-1] : nil,
                                 next_ev: ind == count-1 ? nil : thread.events[ind+1],
                                 damus_state: damus
                        )
                        .contextMenu{MenuItems(event: ev, keypair: damus.keypair, target_pubkey: ev.pubkey)}
                        .onTapGesture {
                            if thread.initial_event.id == ev.id {
                                //dismiss()
                                toggle_thread_view()
                            } else {
                                thread.set_active_event(ev, privkey: damus.keypair.privkey)
                            }
                        }
                        .environmentObject(thread)
                    }
                    
                }
                .padding(.horizontal)
                .padding(.top)
                
                EndBlock()
            }
            .onReceive(NotificationCenter.default.publisher(for: .select_quote)) { notif in
                let ev = notif.object as! NostrEvent
                if ev.id != thread.initial_event.id {
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
            .onAppear() {
                scroll_to_event(scroller: scroller, id: thread.initial_event.id, delay: 0.1, animate: false)
            }
        }
    }
    
    func toggle_thread_view() {
        NotificationCenter.default.post(name: .toggle_thread_view, object: nil)
    }
}




struct ChatroomView_Previews: PreviewProvider {
    @State var events = [NostrEvent(content: "hello", pubkey: "pubkey")]
    
    static var previews: some View {
        let state = test_damus_state()
        ChatroomView(damus: state)
            .environmentObject(ThreadModel(evid: "&849ab9bb263ed2819db06e05f1a1a3b72878464e8c7146718a2fc1bf1912f893", damus_state: state))
        
    }
}
