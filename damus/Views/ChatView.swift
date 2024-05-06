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
    var thread: ThreadModel
    
    @State var expand_reply: Bool = false

    var just_started: Bool {
        return prev_ev == nil || prev_ev!.pubkey != event.pubkey
    }
    
    func next_replies_to_this() -> Bool {
        guard let next = next_ev else {
            return false
        }
        
        return damus_state.events.replies.lookup(next.id) != nil
    }
    
    func is_reply_to_prev(ref_id: NoteId) -> Bool {
        guard let prev = prev_ev else {
            return true
        }
        
        if let rep = damus_state.events.replies.lookup(event.id) {
            return rep.contains(prev.id)
        }
        
        return false
    }
    
    var is_active: Bool {
        return thread.event.id == event.id
    }
    
    func prev_reply_is_same() -> NoteId? {
        return damus.prev_reply_is_same(event: event, prev_ev: prev_ev, replies: damus_state.events.replies)
    }
    
    func reply_is_new() -> NoteId? {
        guard let prev = self.prev_ev else {
            // if they are both null they are the same?
            return nil
        }
        
        if damus_state.events.replies.lookup(prev.id) != damus_state.events.replies.lookup(event.id) {
            return prev.id
        }
        
        return nil
    }
    
    @Environment(\.colorScheme) var colorScheme
    
    var disable_animation: Bool {
        self.damus_state.settings.disable_animation
    }
    
    var options: EventViewOptions {
        if expand_reply {
            return [.no_previews, .no_action_bar]
        } else {
            return [.no_previews, .no_action_bar, .truncate_content]
        }
    }

    var body: some View {
        HStack {
            VStack {
                if is_active || just_started {
                    ProfilePicView(pubkey: event.pubkey, size: 32, highlight: is_active ? .main : .none, profiles: damus_state.profiles, disable_animation: disable_animation)
                }

                Spacer()
            }
            .frame(maxWidth: 32)
            
            Group {
                VStack(alignment: .leading) {
                    HStack {
                        ProfileName(pubkey: event.pubkey, damus: damus_state)
                            .foregroundColor(colorScheme == .dark ?  id_to_color(event.pubkey) : Color.black)
                            //.shadow(color: Color.black, radius: 2)
                        Text(verbatim: "\(format_relative_time(event.created_at))")
                                .foregroundColor(.gray)
                    }

                    if let replying_to = event.direct_replies(damus_state.keypair).first,
                       let prev = self.prev_ev,
                       replying_to != prev.id
                    {
                        //if !is_reply_to_prev(ref_id) {
                        ReplyQuoteView(keypair: damus_state.keypair, quoter: event, event_id: replying_to, state: damus_state, thread: thread, options: options)
                            .onTapGesture {
                                expand_reply = !expand_reply
                            }
                    }

                    let blur_images = should_blur_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)
                    NoteContentView(damus_state: damus_state, event: event, blur_images: blur_images, size: .normal, options: [])

                    if is_active || next_ev == nil || next_ev!.pubkey != event.pubkey {
                        let bar = make_actionbar_model(ev: event.id, damus: damus_state)
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


func prev_reply_is_same(event: NostrEvent, prev_ev: NostrEvent?, replies: ReplyMap) -> NoteId? {
    if let prev = prev_ev {
        if let prev_reply_id = replies.lookup(prev.id) {
            if let cur_reply_id = replies.lookup(event.id) {
                if prev_reply_id != cur_reply_id {
                    return cur_reply_id.first
                }
            }
        }
    }
    return nil
}
    

func id_to_color(_ pubkey: Pubkey) -> Color {
    return Color(
        .sRGB,
        red: Double(pubkey.id[0]) / 255,
        green: Double(pubkey.id[1]) / 255,
        blue:  Double(pubkey.id[2]) / 255,
        opacity: 1
    )

}
