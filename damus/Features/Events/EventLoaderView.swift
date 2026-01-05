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
    @State var not_found: Bool = false
    @State var loadingTask: Task<Void, Never>? = nil
    let content: (NostrEvent) -> Content

    init(damus_state: DamusState, event_id: NoteId, @ViewBuilder content: @escaping (NostrEvent) -> Content) {
        self.damus_state = damus_state
        self.event_id = event_id
        self.content = content
        let event = damus_state.events.lookup(event_id)
        _event = State(initialValue: event)
        Log.debug("EventLoaderView init for %s, cache %s", for: .render, event_id.hex(), event != nil ? "HIT" : "MISS")
    }

    func unsubscribe() {
        self.loadingTask?.cancel()
    }

    /// Streams until the event is found or EOSE is received from all sources.
    @MainActor
    func subscribe() {
        self.loadingTask?.cancel()
        self.not_found = false
        Log.debug("EventLoaderView subscribe started for %s", for: .render, event_id.hex())
        self.loadingTask = Task {
            let filter = NostrFilter(ids: [self.event_id], limit: 1)
            for await lender in damus_state.nostrNetwork.reader.streamExistingEvents(filters: [filter]) {
                guard !Task.isCancelled else {
                    Log.debug("EventLoaderView cancelled for %s", for: .render, self.event_id.hex())
                    return
                }
                let foundEvent = lender.justGetACopy()
                Log.debug("EventLoaderView FOUND event %s", for: .render, self.event_id.hex())
                await MainActor.run {
                    event = foundEvent
                }
                return
            }
            guard !Task.isCancelled else {
                Log.debug("EventLoaderView cancelled (post-stream) for %s", for: .render, self.event_id.hex())
                return
            }
            Log.debug("EventLoaderView NOT FOUND for %s", for: .render, self.event_id.hex())
            await MainActor.run {
                not_found = true
            }
        }
    }

    func load() {
        subscribe()
    }

    var body: some View {
        VStack {
            if let event {
                self.content(event)
            } else if not_found {
                Text("Note not found", comment: "Displayed when a quoted or embedded note cannot be loaded")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ProgressView().padding()
            }
        }
        .onAppear {
            guard event == nil, !not_found else {
                Log.debug("EventLoaderView onAppear skipped for %s (event: %s, not_found: %s)", for: .render, event_id.hex(), event != nil ? "YES" : "NO", not_found ? "YES" : "NO")
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
