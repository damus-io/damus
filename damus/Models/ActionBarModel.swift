//
//  ActionBarModel.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation


class ActionBarModel: ObservableObject {
    @Published var our_like: NostrEvent?
    @Published var our_boost: NostrEvent?
    @Published var our_zap: Zap?
    @Published var likes: Int
    @Published var boosts: Int
    @Published var zaps: Int
    @Published var zap_total: Int64
    
    static func empty() -> ActionBarModel {
        return ActionBarModel(likes: 0, boosts: 0, zaps: 0, zap_total: 0, our_like: nil, our_boost: nil, our_zap: nil)
    }
    
    init(likes: Int, boosts: Int, zaps: Int, zap_total: Int64, our_like: NostrEvent?, our_boost: NostrEvent?, our_zap: Zap?) {
        self.likes = likes
        self.boosts = boosts
        self.zaps = zaps
        self.zap_total = zap_total
        self.our_like = our_like
        self.our_boost = our_boost
        self.our_zap = our_zap
    }
    
    func update(damus: DamusState, evid: String) {
        self.likes = damus.likes.counts[evid] ?? 0
        self.boosts = damus.boosts.counts[evid] ?? 0
        self.zaps = damus.zaps.event_counts[evid] ?? 0
        self.zap_total = damus.zaps.event_totals[evid] ?? 0
        self.our_like = damus.likes.our_events[evid]
        self.our_boost = damus.boosts.our_events[evid]
        self.our_zap = damus.zaps.our_zaps[evid]?.first
        self.objectWillChange.send()
    }
    
    var is_empty: Bool {
        return likes == 0 && boosts == 0 && zaps == 0
    }
    
    var zapped: Bool {
        return our_zap != nil
    }
    
    var liked: Bool {
        return our_like != nil
    }
    
    var boosted: Bool {
        return our_boost != nil
    }
}
