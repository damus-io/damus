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
        
        // Is current event
        if id == subscription_uuid {
            if event != nil {
                return
            }
            
            event = nostr_event
            
            unsubscribe()
        }
    }
    
    func load() {
        subscribe(filters: [
            NostrFilter(
                ids: [self.event_id],
                limit: 1
            )
        ])
    }
    
    var body: some View {
        VStack {
            if let event = event {
                let ev = event.inner_event ?? event
                NavigationLink(destination: BuildThreadV2View(damus: damus, event_id: ev.id)) {
                    EventView(damus: damus, event: event, show_friend_icon: true, size: .small, embedded: true)
                }.buttonStyle(.plain)
            } else {
                ProgressView().padding()
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .border(Color.gray.opacity(0.2), width: 1)
        .cornerRadius(2)
        .onAppear {
            self.load()
        }
    }
}

struct BuilderEventView_Previews: PreviewProvider {
    static var previews: some View {
        BuilderEventView(damus: test_damus_state(), event_id: "536bee9e83c818e3b82c101935128ae27a0d4290039aaf253efe5f09232c1962")
    }
}

