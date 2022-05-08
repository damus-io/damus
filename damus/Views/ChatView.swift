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
    
    let damus: DamusState
    
    @EnvironmentObject var profiles: Profiles
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
        if let prev = prev_ev {
            if let prev_reply_id = thread.replies.lookup(prev.id) {
                if let cur_reply_id = thread.replies.lookup(event.id) {
                    if prev_reply_id != cur_reply_id {
                        return cur_reply_id
                    }
                }
            }
        }
        return nil
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
        Text("\(reply_desc(profiles: profiles, event: event))")
            .font(.footnote)
            .foregroundColor(.gray)
            .frame(alignment: .leading)
    }
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let profile = profiles.lookup(id: event.pubkey)
        HStack {
            //ZStack {
                //Rectangle()
                    //.foregroundColor(Color.gray)
                    //.frame(width: 2)
                
                VStack {
                    if is_active || just_started {
                        ProfilePicView(picture: profile?.picture, size: 32, highlight: is_active ? .main : .none, image_cache: damus.image_cache)
                    }
                    /*
                    if just_started {
                        ProfilePicView(picture: profile?.picture, size: 32, highlight: thread.event.id == event.id ? .main : .none)
                    } else {
                        Text("\(format_relative_time(event.created_at))")
                            .font(.footnote)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                     */

                    Spacer()
                }
                .frame(maxWidth: 32)
            //}
            
            Group {
                VStack(alignment: .leading) {
                    if just_started {
                        HStack {
                            ProfileName(pubkey: event.pubkey, profile: profile)
                                .foregroundColor(colorScheme == .dark ?  id_to_color(event.pubkey) : Color.black)
                                //.shadow(color: Color.black, radius: 2)
                            Text("\(format_relative_time(event.created_at))")
                                    .foregroundColor(.gray)
                        }
                    }
                
                    if let ref_id = thread.replies.lookup(event.id) {
                        if !is_reply_to_prev() {
                            ReplyQuoteView(quoter: event, event_id: ref_id, image_cache: damus.image_cache)
                                .environmentObject(thread)
                                .environmentObject(profiles)
                            ReplyDescription
                        }
                    }

                    NoteContentView(event: event, profiles: profiles, content: event.content)
                    
                    if is_active || next_ev == nil || next_ev!.pubkey != event.pubkey {
                        EventActionBar(event: event,
                                       our_pubkey: damus.pubkey,
                                       bar: make_actionbar_model(ev: event, counter: damus.likes)
                        )
                            .environmentObject(profiles)
                    }

                    //Spacer()
                }
                .padding(6)
            }
            .padding([.leading], 2)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8.0)
            
            //.border(Color.red)
        }
        .contentShape(Rectangle())
        .id(event.id)
        .frame(minHeight: just_started ? PFP_SIZE : 0)
        .padding([.bottom], next_ev == nil ? 30 : 0)
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


