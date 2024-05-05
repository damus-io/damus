//
//  EventShell.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

@MainActor
struct EventShell<Content: View>: View {
    let state: DamusState
    let event: NostrEvent
    let pubkey: Pubkey
    let options: EventViewOptions
    let content: Content
    
    init(state: DamusState, event: NostrEvent, pubkey: Pubkey, options: EventViewOptions, @ViewBuilder content: () -> Content) {
        self.state = state
        self.event = event
        self.options = options
        self.pubkey = pubkey
        self.content = content()
    }

    init(state: DamusState, event: NostrEvent, options: EventViewOptions, @ViewBuilder content: () -> Content) {
        self.state = state
        self.event = event
        self.options = options
        self.pubkey = event.pubkey
        self.content = content()
    }
    
    var has_action_bar: Bool {
        !options.contains(.no_action_bar)
    }
    
    func get_mention(ndb: Ndb) -> Mention<NoteId>? {
        if self.options.contains(.nested) || self.options.contains(.no_mentions) {
            return nil
        }
        
        return first_eref_mention(ndb: ndb, ev: event, keypair: state.keypair)
    }
    
    var ActionBar: some View {
        return EventActionBar(damus_state: state, event: event)
            .padding([.top], 4)
    }

    func Pfp(is_anon: Bool) -> some View {
        return MaybeAnonPfpView(state: state, is_anon: is_anon, pubkey: pubkey, size: options.contains(.small_pfp) ? eventview_pfp_size(.small) : PFP_SIZE )
    }

    var Threaded: some View {
        HStack(alignment: .top) {
        
            let is_anon = event_is_anonymous(ev: event)
            VStack {
                Pfp(is_anon: is_anon)
                
                Spacer()
            }

            VStack(alignment: .leading) {
                EventTop(state: state, event: event, pubkey: pubkey, is_anon: is_anon)

                UserStatusView(status: state.profiles.profile_data(pubkey).status, show_general: state.settings.show_general_statuses, show_music: state.settings.show_music_statuses)

                if !options.contains(.no_replying_to) {
                    ReplyPart(events: state.events, event: event, keypair: state.keypair, ndb: state.ndb)
                }
                
                content

                if let mention = get_mention(ndb: state.ndb) {
                    MentionView(damus_state: state, mention: mention)
                }
                
                if has_action_bar {
                    ActionBar
                }
            }
            .padding([.leading], 2)
        }
    }

    var Wide: some View {
        VStack(alignment: .leading) {
            let is_anon = event_is_anonymous(ev: event)
            
            HStack(spacing: 10) {
                Pfp(is_anon: is_anon)

                VStack(alignment: .leading, spacing: 2) {
                    EventTop(state: state, event: event, pubkey: pubkey, is_anon: is_anon)
                    UserStatusView(status: state.profiles.profile_data(pubkey).status, show_general: state.settings.show_general_statuses, show_music: state.settings.show_music_statuses)
                    ReplyPart(events: state.events, event: event, keypair: state.keypair, ndb: state.ndb)
                    ProxyView(event: event)
                }
            }
            .padding(.horizontal)

            content
            
            if !options.contains(.no_mentions),
               let mention = get_mention(ndb: state.ndb)
            {
                MentionView(damus_state: state, mention: mention)
                    .padding(.horizontal)
            }
            
            if has_action_bar {
                ActionBar
                    .padding(.horizontal)
            }
        }
    }

    var body: some View {
        Group {
            if options.contains(.wide) {
                Wide
            } else {
                Threaded
            }
        }
        .contentShape(Rectangle())
        .id(event.id)
        .padding([.bottom], 2)
    }
}

struct EventShell_Previews: PreviewProvider {

    static var previews: some View {
        VStack {
            EventShell(state: test_damus_state, event: test_note, options: [.no_action_bar]) {
                Text(verbatim: "Hello")
            }

            EventShell(state: test_damus_state, event: test_note, options: [.no_action_bar, .wide]) {
                Text(verbatim: "Hello")
            }
        }
        .frame(height: 300)
    }
}
