//
//  EventsModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation

class EventsModel: ObservableObject {
    let state: DamusState
    let target: NoteId
    let kind: QueryKind
    let profiles_id = UUID().uuidString
    var events: EventHolder
    @Published var loading: Bool
    var loadingTask: Task<Void, Never>?

    enum QueryKind {
        case kind(NostrKind)
        case quotes
    }

    init(state: DamusState, target: NoteId, kind: NostrKind) {
        self.state = state
        self.target = target
        self.kind = .kind(kind)
        self.loading = true
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: state, events: [ev])
        })
    }
    
    init(state: DamusState, target: NoteId, query: EventsModel.QueryKind) {
        self.state = state
        self.target = target
        self.kind = query
        self.loading = true
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: state, events: [ev])
        })
    }
    
    public static func quotes(state: DamusState, target: NoteId) -> EventsModel {
        EventsModel(state: state, target: target, query: .quotes)
    }
    
    public static func reposts(state: DamusState, target: NoteId) -> EventsModel {
        EventsModel(state: state, target: target, kind: .boost)
    }
    
    public static func likes(state: DamusState, target: NoteId) -> EventsModel {
        EventsModel(state: state, target: target, kind: .like)
    }

    private func get_filter() -> NostrFilter {
        var filter: NostrFilter
        switch kind {
        case .kind(let k):
            filter = NostrFilter(kinds: [k])
            filter.referenced_ids = [target]
        case .quotes:
            filter = NostrFilter(kinds: [.text])
            filter.quotes = [target]
        }
        filter.limit = 500
        return filter
    }
    
    func subscribe() {
        loadingTask?.cancel()
        loadingTask = Task {
            DispatchQueue.main.async { self.loading = true }
            outerLoop: for await item in state.nostrNetwork.reader.subscribe(filters: [get_filter()]) {
                switch item {
                case .event(let lender):
                    Task {
                        await lender.justUseACopy({ event in
                            if await events.insert(event) {
                                DispatchQueue.main.async { self.objectWillChange.send() }
                            }
                        })
                    }
                case .eose:
                    DispatchQueue.main.async { self.loading = false }
                    break outerLoop
                }
            }
            DispatchQueue.main.async { self.loading = false }
            guard let txn = NdbTxn(ndb: self.state.ndb) else { return }
            load_profiles(context: "events_model", load: .from_events(events.all_events), damus_state: state, txn: txn)
        }
    }
    
    func unsubscribe() {
        loadingTask?.cancel()
    }

    @MainActor
    private func handle_event(relay_id: RelayURL, ev: NostrEvent) {
        if events.insert(ev) {
            objectWillChange.send()
        }
    }
}
