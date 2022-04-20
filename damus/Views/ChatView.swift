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

    @EnvironmentObject var profiles: Profiles
    @EnvironmentObject var thread: ThreadModel
    
    var just_started: Bool {
        return prev_ev == nil || prev_ev!.pubkey != event.pubkey
    }
    
    var is_active: Bool {
        thread.event.id == event.id
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
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var body: some View {
        let profile = profiles.lookup(id: event.pubkey)
        HStack {
            VStack {
                if is_active || just_started {
                    ProfilePicView(picture: profile?.picture, size: 32, highlight: is_active ? .main : .none)
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

            VStack {
                if just_started {
                    HStack {
                            ProfileName(pubkey: event.pubkey, profile: profile)
                            Text("\(format_relative_time(event.created_at))")
                                .foregroundColor(.gray)
                            Spacer()
                    }
                }
            
                if let ref_id = thread.replies.lookup(event.id) {
                    ReplyQuoteView(quoter: event, event_id: ref_id)
                        .environmentObject(thread)
                        .environmentObject(profiles)
                    ReplyDescription
                }

                Text(event.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                
                if next_ev == nil || next_ev!.pubkey != event.pubkey {
                    EventActionBar(event: event)
                        .environmentObject(profiles)
                }

                Spacer()
            }
            .padding([.leading], 2)
            //.border(Color.red)
        }
        .contentShape(Rectangle())
        .id(event.id)
        .frame(minHeight: just_started ? PFP_SIZE : 0)
        .padding([.bottom], next_ev == nil ? 4 : 0)
        .onTapGesture {
            if is_active {
                convert_to_thread()
            } else {
                thread.event = event
            }
        }
        //.border(Color.green)
        
    }
    
    @Environment(\.presentationMode) var presmode
    
    func dismiss() {
        presmode.wrappedValue.dismiss()
    }
    
    func convert_to_thread() {
        NotificationCenter.default.post(name: .convert_to_thread, object: nil)
    }
}

extension Notification.Name {
    static var convert_to_thread: Notification.Name {
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
