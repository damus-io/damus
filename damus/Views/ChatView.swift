//
//  ChatView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI

fileprivate let CORNER_RADIUS: CGFloat = 10

struct ChatView: View {
    let event: NostrEvent
    let prev_ev: NostrEvent?
    let next_ev: NostrEvent?

    let damus_state: DamusState
    var thread: ThreadModel
    let scroll_to_event: ((_ id: NoteId) -> Void)?
    let highlight_bubble: Bool

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
        return [.no_previews, .no_action_bar, .truncate_content_very_short, .no_show_more, .no_translate, .no_media]
    }
    
    var profile_picture_view: some View {
        VStack {
            if is_active || just_started {
                ProfilePicView(pubkey: event.pubkey, size: 32, highlight: .none, profiles: damus_state.profiles, disable_animation: disable_animation)
                    .onTapGesture {
                        show_profile_action_sheet_if_enabled(damus_state: damus_state, pubkey: event.pubkey)
                    }
            }
        }
        .frame(maxWidth: 32)
    }
    
    var by_other_user: Bool {
        return event.pubkey != damus_state.pubkey
    }
    
    var event_bubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if by_other_user {
                    HStack {
                        ProfileName(pubkey: event.pubkey, damus: damus_state)
                            .foregroundColor(id_to_color(event.pubkey))
                            .onTapGesture {
                                show_profile_action_sheet_if_enabled(damus_state: damus_state, pubkey: event.pubkey)
                            }
                        Text(verbatim: "\(format_relative_time(event.created_at))")
                            .foregroundColor(.gray)
                    }
                }

                if let replying_to = event.direct_replies(damus_state.keypair).first,
                   let prev = self.prev_ev,
                   replying_to != prev.id
                {
                    ReplyQuoteView(keypair: damus_state.keypair, quoter: event, event_id: replying_to, state: damus_state, thread: thread, options: options)
                        .onTapGesture {
                            self.scroll_to_event?(replying_to)
                        }
                        .foregroundColor(by_other_user ? nil : Color.white.opacity(0.9))
                }
                
                HStack {
                    let blur_images = should_blur_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)
                    NoteContentView(damus_state: damus_state, event: event, blur_images: blur_images, size: .normal, options: [])
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(by_other_user ? Color.secondary.opacity(0.1) : Color.accentColor)
        .foregroundColor(by_other_user ? nil : Color.white)
        .cornerRadius(CORNER_RADIUS)
        .contextMenu(menuItems: {
            let bar = make_actionbar_model(ev: event.id, damus: damus_state)
            Group {
                EventActionBar(damus_state: damus_state, event: self.event, bar: bar, options: [.context_menu])
                
                Menu {
                    MenuItems(damus_state: damus_state, event: self.event, target_pubkey: event.pubkey, profileModel: ProfileModel(pubkey: event.pubkey, damus: damus_state))
                } label: {
                    Text("More", comment: "Context menu option to show more options")
                }
            }
        })
        .padding(4)
        .overlay(
            RoundedRectangle(cornerRadius: CORNER_RADIUS+2)
                .stroke(.accent, lineWidth: 4)
                .opacity(highlight_bubble ? 1 : 0)
        )
    }
    
    var action_bar: some View {
        let bar = make_actionbar_model(ev: event.id, damus: damus_state)
        return HStack {
            if by_other_user {
                Spacer()
            }
            if !bar.is_empty {
                EventActionBar(damus_state: damus_state, event: event, bar: bar, options: [.no_spread, .hide_items_without_activity])
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(100)
                    .shadow(color: Color.black.opacity(0.1),radius: 5, y: 5)
            }
            if !by_other_user {
                Spacer()
            }
        }
        .padding(.top, -35)
        .padding(.horizontal, 10)
    }

    var body: some View {
        VStack {
            HStack(alignment: .bottom, spacing: 4) {
                if by_other_user {
                    self.profile_picture_view
                }
                
                self.event_bubble
                
                if !by_other_user {
                    self.profile_picture_view
                }
            }
            .contentShape(Rectangle())
            .id(event.id)
            .padding([.bottom], 6)
            
            self.action_bar
        }

    }
}

extension Notification.Name {
    static var toggle_thread_view: Notification.Name {
        return Notification.Name("convert_to_thread")
    }
}


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

#Preview {
    ChatView(event: test_note, prev_ev: nil, next_ev: nil, damus_state: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state), scroll_to_event: nil, highlight_bubble: false, expand_reply: false)
}

#Preview {
    ChatView(event: test_short_note, prev_ev: nil, next_ev: nil, damus_state: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state), scroll_to_event: nil, highlight_bubble: false, expand_reply: false)
}

#Preview {
    ChatView(event: test_short_note, prev_ev: nil, next_ev: nil, damus_state: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state), scroll_to_event: nil, highlight_bubble: true, expand_reply: false)
}
