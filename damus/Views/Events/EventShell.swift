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
    let options: EventViewOptions
    let content: Content
    
    init(state: DamusState, event: NostrEvent, options: EventViewOptions, @ViewBuilder content: () -> Content) {
        self.state = state
        self.event = event
        self.options = options
        self.content = content()
    }
    
    var has_action_bar: Bool {
        !options.contains(.no_action_bar)
    }
    
    func get_mention() -> Mention? {
        if self.options.contains(.nested) {
            return nil
        }
        
        return first_eref_mention(ev: event, privkey: state.keypair.privkey)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            let is_anon = event_is_anonymous(ev: event)
            
            HStack(spacing: 10) {
                MaybeAnonPfpView(state: state, is_anon: is_anon, pubkey: event.pubkey, size: options.contains(.small_pfp) ? eventview_pfp_size(.small) : PFP_SIZE )
                
                VStack {
                    EventTop(state: state, event: event, is_anon: is_anon)
                    ReplyPart(event: event, privkey: state.keypair.privkey, profiles: state.profiles)
                }
            }
            .padding(.horizontal)

            content
            
            if !options.contains(.no_mentions), let mention = get_mention() {

                BuilderEventView(damus: state, event_id: mention.ref.id)
                    .padding(.horizontal)
            }
            
            if has_action_bar {
                //EmptyRect
                EventActionBar(damus_state: state, event: event)
                    .padding(.horizontal)
            }
        }
    }
}

struct EventShell_Previews: PreviewProvider {
    static var previews: some View {
        EventShell(state: test_damus_state(), event: test_event, options: [.no_action_bar]) {
            Text("Hello")
        }
    }
}
