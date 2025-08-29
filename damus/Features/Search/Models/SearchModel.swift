//
//  Timeline.swift
//  damus
//
//  Created by William Casarin on 2022-05-09.
//

import Foundation


class SearchModel: ObservableObject {
    let state: DamusState
    var events: EventHolder
    @Published var loading: Bool = false
    
    var search: NostrFilter
    let profiles_subid = UUID().description
    var listener: Task<Void, Never>? = nil
    let limit: UInt32 = 500
    
    init(state: DamusState, search: NostrFilter) {
        self.state = state
        self.search = search
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: state, events: [ev])
        })
    }
    
    func filter_muted()  {
        self.events.filter {
            should_show_event(state: state, ev: $0)
        }
        self.objectWillChange.send()
    }
    
    func subscribe() {
        // since 1 month
        search.limit = self.limit
        search.kinds = [.text, .like, .longform, .highlight, .follow_list]

        //likes_filter.ids = ref_events.referenced_ids!
        listener?.cancel()
        listener = Task {
            self.loading = true
            print("subscribing to search")
            for await item in await state.nostrNetwork.reader.subscribe(filters: [search]) {
                switch item {
                case .event(let borrow):
                    try? borrow { ev in
                        let event = ev.toOwned()
                        if event.is_textlike && event.should_show_event {
                            self.add_event(event)
                        }
                    }
                case .eose:
                    break
                }
                guard let txn = NdbTxn(ndb: state.ndb) else { return }
                load_profiles(context: "search", load: .from_events(self.events.all_events), damus_state: state, txn: txn)
            }
            self.loading = false
        }
    }
    
    func unsubscribe() {
        listener?.cancel()
        listener = nil
    }
    
    func add_event(_ ev: NostrEvent) {
        if !event_matches_filter(ev, filter: search) {
            return
        }
        
        guard should_show_event(state: state, ev: ev) else {
            return
        }
        
        if self.events.insert(ev) {
            objectWillChange.send()
        }
    }
}

func event_matches_hashtag(_ ev: NostrEvent, hashtags: [String]) -> Bool {
    for tag in ev.tags {
        if tag_is_hashtag(tag) && hashtags.contains(tag[1].string()) {
            return true
        }
    }
    return false
}

func tag_is_hashtag(_ tag: Tag) -> Bool {
    // "hashtag" is deprecated, will remove in the future
    return tag.count >= 2 && tag[0].matches_char("t")
}

func event_matches_filter(_ ev: NostrEvent, filter: NostrFilter) -> Bool {
    if let hashtags = filter.hashtag {
        return event_matches_hashtag(ev, hashtags: hashtags)
    }
    return true
}
