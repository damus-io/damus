//
//  EventShell.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct EventShell<Content: View>: View {
    let state: DamusState
    let event: NostrEvent
    let pubkey: String
    let options: EventViewOptions
    let content: Content
    
    init(state: DamusState, event: NostrEvent, pubkey: String, options: EventViewOptions, @ViewBuilder content: () -> Content) {
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
    
    func get_mention() -> Mention? {
        if self.options.contains(.nested) || self.options.contains(.no_mentions) {
            return nil
        }
        
        return first_eref_mention(ev: event, privkey: state.keypair.privkey)
    }

    func Mention(_ mention: Mention) -> some View {
        return BuilderEventView(damus: state, event_id: mention.ref.id)
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

                if !options.contains(.no_replying_to) {
                    ReplyPart(event: event, privkey: state.keypair.privkey, profiles: state.profiles)
                }
                
                content

                if let mention = get_mention() {
                    Mention(mention)
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

                VStack {
                    EventTop(state: state, event: event, pubkey: pubkey, is_anon: is_anon)
                    ReplyPart(event: event, privkey: state.keypair.privkey, profiles: state.profiles)
                }
            }
            .padding(.horizontal)

            content
            
            if !options.contains(.no_mentions), let mention = get_mention() {
                Mention(mention)
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
        .frame(maxWidth: .infinity, minHeight: PFP_SIZE)
        .padding([.bottom], 2)
    }
}

struct EventShell_Previews: PreviewProvider {

    static var previews: some View {
        VStack {
            EventShell(state: test_damus_state(), event: test_event, options: [.no_action_bar]) {
                Text(verbatim: "Hello")
            }

            EventShell(state: test_damus_state(), event: test_event, options: [.no_action_bar, .wide]) {
                Text(verbatim: "Hello")
            }
        }
        .frame(height: 300)
    }
}
