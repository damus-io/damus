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
    @State var loadingTask: Task<Void, Never>? = nil
    let content: (NostrEvent) -> Content
    
    init(damus_state: DamusState, event_id: NoteId, @ViewBuilder content: @escaping (NostrEvent) -> Content) {
        self.damus_state = damus_state
        self.event_id = event_id
        self.content = content
        let event = damus_state.events.lookup(event_id)
        _event = State(initialValue: event)
    }
    
    func unsubscribe() {
        self.loadingTask?.cancel()
    }
    
    func subscribe(filters: [NostrFilter]) {
        self.loadingTask?.cancel()
        self.loadingTask = Task {
            for await item in await damus_state.nostrNetwork.reader.subscribe(filters: filters) {
                switch item {
                case .event(let borrow):
                    try? borrow { ev in
                        event = ev.toOwned()
                    }
                    break
                case .eose:
                    break
                }
            }
        }
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
