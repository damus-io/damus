//
//  BuilderEventView.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

struct BuilderEventView: View {
    let damus: DamusState
    let event_id: NoteId
    let event: NostrEvent?
    
    init(damus: DamusState, event: NostrEvent) {
        self.event = event
        self.damus = damus
        self.event_id = event.id
    }
    
    init(damus: DamusState, event_id: NoteId) {
        self.event_id = event_id
        self.damus = damus
        self.event = nil
    }
    
    func Event(event: NostrEvent) -> some View {
        return EventView(damus: damus, event: event, options: .embedded)
            .padding([.top, .bottom], 8)
            .onTapGesture {
                let ev = event.get_inner_event(cache: damus.events) ?? event
                let thread = ThreadModel(event: ev, damus_state: damus)
                damus.nav.push(route: .Thread(thread: thread))
            }
    }
    
    var body: some View {
        VStack {
            if let event {
                self.Event(event: event)
            } else {
                EventLoaderView(damus_state: damus, event_id: self.event_id) { loaded_event in
                    self.Event(event: loaded_event)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1.0)
        )
    }
}

struct BuilderEventView_Previews: PreviewProvider {
    static var previews: some View {
        BuilderEventView(damus: test_damus_state, event_id: test_note.id)
    }
}

