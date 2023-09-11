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
    @State var event: NostrEvent?
    @State var subscription_uuid: String = UUID().description
    
    init(damus: DamusState, event: NostrEvent) {
        _event = State(initialValue: event)
        self.damus = damus
        self.event_id = event.id
    }
    
    init(damus: DamusState, event_id: NoteId) {
        let event = damus.events.lookup(event_id)
        self.event_id = event_id
        self.damus = damus
        _event = State(initialValue: event)
    }
    
    func unsubscribe() {
        damus.pool.unsubscribe(sub_id: subscription_uuid)
    }
    
    func subscribe(filters: [NostrFilter]) {
        damus.pool.register_handler(sub_id: subscription_uuid, handler: handle_event)
        damus.pool.send(.subscribe(.init(filters: filters, sub_id: subscription_uuid)))
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
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
                EventView(damus: damus, event: event, options: .embedded)
                    .padding([.top, .bottom], 8)
                    .onTapGesture {
                        let ev = event.get_inner_event(cache: damus.events) ?? event
                        let thread = ThreadModel(event: ev, damus_state: damus)
                        damus.nav.push(route: .Thread(thread: thread))
                    }
            } else {
                ProgressView().padding()
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1.0)
        )
        .onAppear {
            guard event == nil else {
                return
            }
            self.load()
        }
    }
}

struct BuilderEventView_Previews: PreviewProvider {
    static var previews: some View {
        BuilderEventView(damus: test_damus_state, event_id: test_note.id)
    }
}

