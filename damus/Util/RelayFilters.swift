//
//  RelayFilters.swift
//  damus
//
//  Created by William Casarin on 2023-02-08.
//

import Foundation

struct RelayFilter: Hashable {
    let timeline: Timeline
    let relay_id: String
}

class RelayFilters {
    private let our_pubkey: String
    private var disabled: Set<RelayFilter>
    
    func is_filtered(timeline: Timeline, relay_id: String) -> Bool {
        let filter = RelayFilter(timeline: timeline, relay_id: relay_id)
        let contains = disabled.contains(filter)
        return contains
    }
    
    func remove(timeline: Timeline, relay_id: String) {
        let filter = RelayFilter(timeline: timeline, relay_id: relay_id)
        if !disabled.contains(filter) {
            return
        }
        
        disabled.remove(filter)
        save_relay_filters(our_pubkey, filters: disabled)
    }
    
    func insert(timeline: Timeline, relay_id: String) {
        let filter = RelayFilter(timeline: timeline, relay_id: relay_id)
        if disabled.contains(filter) {
            return
        }
        
        disabled.insert(filter)
        save_relay_filters(our_pubkey, filters: disabled)
    }
    
    init(our_pubkey: String) {
        self.our_pubkey = our_pubkey
        disabled = load_relay_filters(our_pubkey)
    }
}

func save_relay_filters(_ pubkey: String, filters: Set<RelayFilter>) {
    let key = pk_setting_key(pubkey, key: "relay_filters")
    let arr = Array(filters.map { filter in "\(filter.timeline)\t\(filter.relay_id)" })
    UserDefaults.standard.set(arr, forKey: key)
}

func load_relay_filters(_ pubkey: String) -> Set<RelayFilter> {
    let key = pk_setting_key(pubkey, key: "relay_filters")
    guard let filters = UserDefaults.standard.stringArray(forKey: key) else {
        return Set()
    }
    
    return filters.reduce(into: Set()) { s, str in
        let parts = str.components(separatedBy: "\t")
        guard parts.count == 2 else {
            return
        }
        guard let timeline = Timeline.init(rawValue: parts[0]) else {
            return
        }
        let filter = RelayFilter(timeline: timeline, relay_id: parts[1])
        s.insert(filter)
    }
}

func determine_to_relays(pool: RelayPool, filters: RelayFilters) -> [String] {
    return pool.descriptors
        .map { $0.url.absoluteString }
        .filter { !filters.is_filtered(timeline: .search, relay_id: $0) }
}
