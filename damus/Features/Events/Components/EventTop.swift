//
//  EventTop.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

@MainActor
struct EventTop: View {
    let state: DamusState
    let event: NostrEvent
    let pubkey: Pubkey
    let is_anon: Bool
    let size: EventViewKind
    let options: EventViewOptions
    
    init(state: DamusState, event: NostrEvent, pubkey: Pubkey, is_anon: Bool, size: EventViewKind, options: EventViewOptions) {
        self.state = state
        self.event = event
        self.pubkey = pubkey
        self.is_anon = is_anon
        self.size = size
        self.options = options
    }
    
    func ProfileName(is_anon: Bool) -> some View {
        let pk = is_anon ? ANON_PUBKEY : self.pubkey
        return EventProfileName(pubkey: pk, damus: state, size: size)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ProfileName(is_anon: is_anon)
            TimeDot()
            RelativeTime(time: state.events.get_cache_data(event.id).relative_time, size: size, font_size: state.settings.font_size)
            if let clientTag = event.clientTag {
                TimeDot()
                ClientTagLabel(clientTag: clientTag, size: size, font_size: state.settings.font_size)
            }
            Spacer()
            if !options.contains(.no_context_menu) {
                EventMenuContext(damus: state, event: event)
            }
        }
        .lineLimit(1)
    }
}

struct EventTop_Previews: PreviewProvider {
    static var previews: some View {
        EventTop(state: test_damus_state, event: test_note, pubkey: test_note.pubkey, is_anon: false, size: .normal, options: [])
    }
}

struct ClientTagLabel: View {
    let clientTag: ClientTagMetadata
    let size: EventViewKind
    let font_size: Double

    var body: some View {
        Text(String(format: NSLocalizedString("via %@", comment: "Label indicating which client published the event"), clientTag.name))
            .font(eventviewsize_to_font(size, font_size: font_size))
            .foregroundColor(.gray)
            .lineLimit(1)
    }
}
