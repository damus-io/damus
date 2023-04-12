//
//  BuilderEventView.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

struct BuilderEventView: View {
    let damus: DamusState
    let event_id: String
    @State var event: NostrEvent?
    @State var subscription_uuid: String = UUID().description
    
    init(damus: DamusState, event: NostrEvent) {
        _event = State(initialValue: event)
        self.damus = damus
        self.event_id = event.id
    }
    
    init(damus: DamusState, event_id: String) {
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
        
        guard nostr_event.known_kind == .text else {
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
            NostrFilter(ids: [self.event_id], limit: 1),
            NostrFilter(
                kinds: [NostrKind.zap.rawValue],
                referenced_ids: [self.event_id]
            )
        ])
    }
    
    var body: some View {
        VStack {
            if let event {
                let ev = event.inner_event ?? event
                let thread = ThreadModel(event: ev, damus_state: damus)
                let dest = ThreadView(state: damus, thread: thread)
                NavigationLink(destination: dest) {
                    EmbeddedEventView(damus_state: damus, event: event)
                        .padding(8)
                }.buttonStyle(.plain)
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
        BuilderEventView(damus: test_damus_state(), event_id: "536bee9e83c818e3b82c101935128ae27a0d4290039aaf253efe5f09232c1962")
    }
}

