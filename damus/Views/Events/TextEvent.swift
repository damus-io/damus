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
    static let no_media = EventViewOptions(rawValue: 1 << 10)
    static let truncate_content_very_short = EventViewOptions(rawValue: 1 << 11)

    static let embedded: EventViewOptions = [.no_action_bar, .small_pfp, .wide, .truncate_content, .nested]
    static let embedded_text_only: EventViewOptions = [.no_action_bar, .small_pfp, .wide, .truncate_content, .nested, .no_media, .truncate_content_very_short]
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
        let blur_imgs = should_blur_images(settings: damus.settings, contacts: damus.contacts, ev: event, our_pubkey: damus.pubkey)
        return NoteContentView(
            damus_state: damus,
            event: event,
            blur_images: blur_imgs,
            size: .normal,
            options: options
        )
    }

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

