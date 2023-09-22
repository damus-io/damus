//
//  TextEvent.swift
//  damus
//
//  Created by William Casarin on 2023-02-03.
//

import SwiftUI

struct EventViewOptions: OptionSet {
    let rawValue: UInt32
    
    static let no_action_bar = EventViewOptions(rawValue: 1 << 0)
    static let no_replying_to = EventViewOptions(rawValue: 1 << 1)
    static let wide = EventViewOptions(rawValue: 1 << 3)
    static let truncate_content = EventViewOptions(rawValue: 1 << 4)
    static let no_translate = EventViewOptions(rawValue: 1 << 5)
    static let small_pfp = EventViewOptions(rawValue: 1 << 6)
    static let nested = EventViewOptions(rawValue: 1 << 7)
    static let top_zap = EventViewOptions(rawValue: 1 << 8)
    static let no_mentions = EventViewOptions(rawValue: 1 << 9)

    static let embedded: EventViewOptions = [.no_action_bar, .small_pfp, .wide, .truncate_content, .nested]
}

struct TextEvent: View {
    let damus: DamusState
    let event: NostrEvent
    let pubkey: Pubkey
    let options: EventViewOptions
    let evdata: EventData
    
    init(damus: DamusState, event: NostrEvent, pubkey: Pubkey, options: EventViewOptions) {
        self.damus = damus
        self.event = event
        self.pubkey = pubkey
        self.options = options
        self.evdata = damus.events.get_cache_data(event.id)
    }
    
    var body: some View {
        EventShell(state: damus, event: event, pubkey: pubkey, options: options) {
            EvBody(options: options)
        }
    }

    func EvBody(options: EventViewOptions) -> some View {
        let show_imgs = should_show_images(settings: damus.settings, contacts: damus.contacts, ev: event, our_pubkey: damus.pubkey)
        return NoteContentView(
            damus_state: damus,
            event: event,
            show_images: show_imgs,
            size: .normal,
            options: options
        )
    }

}

func event_has_tag(ev: NostrEvent, tag: String) -> Bool {
    for t in ev.tags {
        if t.count >= 1 && t[0].matches_str(tag) {
            return true
        }
    }
    
    return false
}


func event_is_anonymous(ev: NostrEvent) -> Bool {
    return ev.known_kind == .zap_request && event_has_tag(ev: ev, tag: "anon")
}

struct TextEvent_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TextEvent(damus: test_damus_state, event: test_note, pubkey: test_pubkey, options: [])
                .frame(height: 400)
            
            TextEvent(damus: test_damus_state, event: test_note, pubkey: test_pubkey, options: [.wide])
                .frame(height: 400)
        }
    }
}

