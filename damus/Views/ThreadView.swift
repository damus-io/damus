//
//  ThreadView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI


struct ThreadView: View {
    @StateObject var thread: ThreadModel
    let damus: DamusState
    @State var is_chatroom: Bool
    @State var seen_first: Bool = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Group {
            if is_chatroom {
                ChatroomView(damus: damus)
                    .navigationBarTitle("Chat")
                    .environmentObject(thread)
            } else {
                EventDetailView(damus: damus, thread: thread)
                    .navigationBarTitle("Thread")
                    .environmentObject(thread)
            }
            
            /*
            NavigationLink(destination: edv, isActive: $is_chatroom) {
                EmptyView()
            }
             */
        }
        .padding([.leading, .trailing], 6)
        .onReceive(NotificationCenter.default.publisher(for: .switched_timeline)) { n in
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggle_thread_view)) { _ in
            is_chatroom = !is_chatroom
            //print("is_chatroom: \(is_chatroom)")
        }
        .onChange(of: thread.events) { val in
            if seen_first {
                return
            }
            if let ev = thread.events.first {
                guard ev.is_root_event() else {
                    return
                }
                seen_first = true
                is_chatroom = has_hashtag(ev.tags, hashtag: "chat")
            }
        }
        .onAppear() {
            thread.subscribe()
        }
        .onDisappear() {
            thread.unsubscribe()
        }
    }
}

/*
struct ThreadView_Previews: PreviewProvider {
    static var previews: some View {
        ThreadView()
    }
}
*/

func has_hashtag(_ tags: [[String]], hashtag: String) -> Bool {
    for tag in tags {
        if tag.count >= 2 && tag[0] == "hashtag" && tag[1] == hashtag {
            return true
        }
    }
    
    return false
}
