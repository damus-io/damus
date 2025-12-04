//
//  LiveEventModel.swift
//  damus
//
//  Created by eric on 7/25/25.
//

import Foundation

/// The data model for the LiveEventHome view
class LiveEventModel: ObservableObject {
    var events: EventHolder
    @Published var loading: Bool = false

    let damus_state: DamusState
    var subscriptionTask: Task<Void, any Error>? = nil
    var seen_dtag: Set<String> = Set()

    @MainActor
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: damus_state, events: [ev])
        })
    }

    @MainActor
    func filter_muted() {
        events.filter { should_show_event(state: damus_state, ev: $0) }
        self.objectWillChange.send()
    }
    
    /// Helper function to set the `loading` member in the correct actor
    @MainActor
    private func set(loading: Bool) {
        self.loading = loading
    }

    func subscribe() {
        subscriptionTask?.cancel()

        subscriptionTask = Task {
            await self.set(loading: true)
            
            var live_event_filter = NostrFilter(kinds: [.live])
            live_event_filter.until = UInt32(Date.now.timeIntervalSince1970)
            let calendar = Calendar.current
            let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date())!
            live_event_filter.since = UInt32(twoWeeksAgo.timeIntervalSince1970)
            
            let to_relays = await damus_state.nostrNetwork.ourRelayDescriptors
                .map { $0.url }
                .filter { !damus_state.relay_filters.is_filtered(timeline: .search, relay_id: $0) }
            
            for await item in damus_state.nostrNetwork.reader.advancedStream(filters: [live_event_filter], to: to_relays) {
                switch item {
                case .event(let lender):
                    await lender.justUseACopy({ await handle_event(ev: $0) })
                case .eose:
                    continue
                case .ndbEose:
                    await self.set(loading: false)
                case .networkEose:
                    continue
                }
            }
        }
    }

    @MainActor
    func unsubscribe() {
        self.set(loading: false)
        subscriptionTask?.cancel()
    }

    func handle_event(ev: NostrEvent) async {
        let should_show_event = await should_show_event(state: damus_state, ev: ev)
        if ev.is_textlike && should_show_event && !ev.is_reply()
        {
            for tag in ev.tags {
                guard tag.count >= 2 else { continue }
                if tag[0].string() == "d" {
                    if seen_dtag.contains(tag[1].string()) {
                        return
                    } else {
                        seen_dtag.insert(tag[1].string())
                    }
                }
            }

            await MainActor.run {
                if self.events.insert(ev) {
                    self.objectWillChange.send()
                }
            }
        }
    }
}
