//
//  EventLoaderView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-09-27.
//

import SwiftUI

/// This view handles the loading logic for Nostr events, so that you can easily use views that require `NostrEvent`, even if you only have a `NoteId`
struct EventLoaderView<Content: View>: View {
    let damus_state: DamusState
    let event_id: NoteId
    @State var event: NostrEvent?
    @State var subscription_uuid: String = UUID().description
    let content: (NostrEvent) -> Content
    
    init(damus_state: DamusState, event_id: NoteId, @ViewBuilder content: @escaping (NostrEvent) -> Content) {
        self.damus_state = damus_state
        self.event_id = event_id
        self.content = content
        let event = damus_state.events.lookup(event_id)
        _event = State(initialValue: event)
    }
    
    func unsubscribe() {
        damus_state.pool.unsubscribe(sub_id: subscription_uuid)
    }
    
    func subscribe(filters: [NostrFilter]) {
        damus_state.pool.register_handler(sub_id: subscription_uuid, handler: handle_event)
        damus_state.pool.send(.subscribe(.init(filters: filters, sub_id: subscription_uuid)))
    }

    func handle_event(relay_id: RelayURL, ev: NostrConnectionEvent) {
        guard case .nostr_event(let nostr_response) = ev else {
            return
        }
        
        guard case .event(let id, let nostr_event) = nostr_response else {
            return
        }
        
        guard id == subscription_uuid else {
            return
        }
        
        if event != nil {
            return
        }
        
        event = nostr_event
        
        unsubscribe()
    }
    
    func load() {
        subscribe(filters: [
            NostrFilter(ids: [self.event_id], limit: 1)
        ])
    }
    
    var body: some View {
        VStack {
            if let event {
                self.content(event)
            } else {
                ProgressView().padding()
            }
        }
        .onAppear {
            guard event == nil else {
                return
            }
            self.load()
        }
    }
}


struct EventLoaderView_Previews: PreviewProvider {
    static var previews: some View {
        EventLoaderView(damus_state: test_damus_state, event_id: test_note.id) { event in
            EventView(damus: test_damus_state, event: event)
        }
    }
}
