//
//  ChatroomView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI

struct ChatroomView: View {
    @EnvironmentObject var thread: ThreadModel
    
    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack {
                    let count = thread.events.count
                    ForEach(Array(zip(thread.events, thread.events.indices)), id: \.0.id) { (ev, ind) in
                        ChatView(event: thread.events[ind],
                                 prev_ev: ind > 0 ? thread.events[ind-1] : nil,
                                 next_ev: ind == count-1 ? nil : thread.events[ind+1]
                        )
                        .environmentObject(thread)
                    }
                }
            }
            .onAppear() {
                scroll_to_event(scroller: scroller, id: thread.event.id, delay: 0.5, animate: true, anchor: .center)
            }
        }
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
