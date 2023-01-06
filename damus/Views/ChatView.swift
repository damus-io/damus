//
//  ChatView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI

struct ChatView: View {
    let event: NostrEvent
    let prev_ev: NostrEvent?
    let next_ev: NostrEvent?
    
    let damus_state: DamusState
    
    @State var expand_reply: Bool = false
    @EnvironmentObject var thread: ThreadModel
    
    var just_started: Bool {
        return prev_ev == nil || prev_ev!.pubkey != event.pubkey
    }
    
    func next_replies_to_this() -> Bool {
        guard let next = next_ev else {
            return false
        }
        
        return thread.replies.lookup(next.id) != nil
    }
    
    func is_reply_to_prev() -> Bool {
        guard let prev = prev_ev else {
            return true
        }
        
        if let rep = thread.replies.lookup(event.id) {
            return rep == prev.id
        }
        
        return false
    }
    
    var is_active: Bool {
        return thread.initial_event.id == event.id
    }
    
    func prev_reply_is_same() -> String? {
        return damus.prev_reply_is_same(event: event, prev_ev: prev_ev, replies: thread.replies)
    }
    
    func reply_is_new() -> String? {
        guard let prev = self.prev_ev else {
            // if they are both null they are the same?
            return nil
        }
        
        if thread.replies.lookup(prev.id) != thread.replies.lookup(event.id) {
            return prev.id
        }
        
        return nil
    }
    
    var ReplyDescription: some View {
        Text("\(reply_desc(profiles: damus_state.profiles, event: event))")
            .font(.footnote)
            .foregroundColor(.gray)
            .frame(alignment: .leading)
    }
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            VStack {
                if is_active || just_started {
                    ProfilePicView(pubkey: event.pubkey, size: 32, highlight: is_active ? .main : .none, profiles: damus_state.profiles)
                }

                Spacer()
            }
            .frame(maxWidth: 32)
            
            Group {
                VStack(alignment: .leading) {
                    if just_started {
                        HStack {
                            ProfileName(pubkey: event.pubkey, profile: damus_state.profiles.lookup(id: event.pubkey), damus: damus_state, show_friend_confirmed: true)
                                .foregroundColor(colorScheme == .dark ?  id_to_color(event.pubkey) : Color.black)
                                //.shadow(color: Color.black, radius: 2)
                            Text("\(format_relative_time(event.created_at))")
                                    .foregroundColor(.gray)
                        }
                    }
                
                    if let ref_id = thread.replies.lookup(event.id) {
                        if !is_reply_to_prev() {
                            ReplyQuoteView(privkey: damus_state.keypair.privkey, quoter: event, event_id: ref_id, profiles: damus_state.profiles, previews: damus_state.previews)
                                .frame(maxHeight: expand_reply ? nil : 100)
                                .environmentObject(thread)
                                .onTapGesture {
                                    expand_reply = !expand_reply
                                }
                            ReplyDescription
                        }
                    }
                    
                    NoteContentView(privkey: damus_state.keypair.privkey, event: event, profiles: damus_state.profiles, previews: damus_state.previews, show_images: should_show_images(contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey), artifacts: .just_content(event.content), size: .normal)

                    if is_active || next_ev == nil || next_ev!.pubkey != event.pubkey {
                        let bar = make_actionbar_model(ev: event, damus: damus_state)
                        EventActionBar(damus_state: damus_state, event: event, bar: bar)
                    }

                    //Spacer()
                }
                .padding(6)
            }
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8.0)
            
            //.border(Color.red)
        }
        .contentShape(Rectangle())
        .id(event.id)
        //.frame(minHeight: just_started ? PFP_SIZE : 0)
        .padding([.bottom], 6)
        //.border(Color.green)
        
    }
}

extension Notification.Name {
    static var toggle_thread_view: Notification.Name {
        return Notification.Name("convert_to_thread")
    }
}


/*
struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView()
    }
}

*/


func prev_reply_is_same(event: NostrEvent, prev_ev: NostrEvent?, replies: ReplyMap) -> String? {
    if let prev = prev_ev {
        if let prev_reply_id = replies.lookup(prev.id) {
            if let cur_reply_id = replies.lookup(event.id) {
                if prev_reply_id != cur_reply_id {
                    return cur_reply_id
                }
            }
        }
    }
    return nil
}
    
