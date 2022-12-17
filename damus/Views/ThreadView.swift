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
    @State var metadata: ChatroomMetadata? = nil
    @State var seen_first: Bool = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Group {
            if is_chatroom {
                ChatroomView(damus: damus)
                    .navigationBarTitle(metadata?.name ?? "Chat")
                    .environmentObject(thread)
            } else {
                EventDetailView(damus: damus, thread: thread)
                    .navigationBarTitle(metadata?.name ?? "Thread")
                    .environmentObject(thread)
            }
            
            /*
            NavigationLink(destination: edv, isActive: $is_chatroom) {
                EmptyView()
            }
             */
        }
        .onReceive(handle_notify(.switched_timeline)) { n in
            dismiss()
        }
        .onReceive(handle_notify(.toggle_thread_view)) { _ in
            is_chatroom = !is_chatroom
            //print("is_chatroom: \(is_chatroom)")
        }
        .onReceive(handle_notify(.chatroom_meta)) { n in
            let meta = n.object as! ChatroomMetadata
            self.metadata = meta
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
                is_chatroom = should_show_chatroom(ev) 
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

func should_show_chatroom(_ ev: NostrEvent) -> Bool {
    if ev.known_kind == .chat || ev.known_kind == .channel_create {
        return true
    }
    
    return has_hashtag(ev.tags, hashtag: "chat")
}

func tag_is_hashtag(_ tag: [String]) -> Bool {
    // "hashtag" is deprecated, will remove in the future
    return tag.count >= 2 && (tag[0] == "hashtag" || tag[0] == "t")
}

func has_hashtag(_ tags: [[String]], hashtag: String) -> Bool {
    for tag in tags {
        if tag_is_hashtag(tag) && tag[1] == hashtag {
            return true
        }
    }
    
    return false
}
