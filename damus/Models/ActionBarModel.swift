//
//  ActionBarModel.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation

enum Zapped {
    case not_zapped
    case pending
    case zapped
}

class ActionBarModel: ObservableObject {
    @Published var our_like: NostrEvent?
    @Published var our_boost: NostrEvent?
    @Published var our_quote_repost: NostrEvent?
    @Published var our_reply: NostrEvent?
    @Published var our_zap: Zapping?
    @Published var likes: Int
    @Published var boosts: Int
    @Published var quote_reposts: Int
    @Published private(set) var zaps: Int
    @Published var zap_total: Int64
    @Published var replies: Int
    
    static func empty() -> ActionBarModel {
        return ActionBarModel(likes: 0, boosts: 0, zaps: 0, zap_total: 0, replies: 0, our_like: nil, our_boost: nil, our_zap: nil, our_reply: nil)
    }
    
    init(likes: Int = 0, boosts: Int = 0, zaps: Int = 0, zap_total: Int64 = 0, replies: Int = 0, our_like: NostrEvent? = nil, our_boost: NostrEvent? = nil, our_zap: Zapping? = nil, our_reply: NostrEvent? = nil, our_quote_repost: NostrEvent? = nil, quote_reposts: Int = 0) {
        self.likes = likes
        self.boosts = boosts
        self.zaps = zaps
        self.replies = replies
        self.zap_total = zap_total
        self.our_like = our_like
        self.our_boost = our_boost
        self.our_zap = our_zap
        self.our_reply = our_reply
        self.our_quote_repost = our_quote_repost
        self.quote_reposts = quote_reposts
    }
    
    func update(damus: DamusState, evid: NoteId) {
        self.likes = damus.likes.counts[evid] ?? 0
        self.boosts = damus.boosts.counts[evid] ?? 0
        self.zaps = damus.zaps.event_counts[evid] ?? 0
        self.replies = damus.replies.get_replies(evid)
        self.quote_reposts = damus.quote_reposts.counts[evid] ?? 0
        self.zap_total = damus.zaps.event_totals[evid] ?? 0
        self.our_like = damus.likes.our_events[evid]
        self.our_boost = damus.boosts.our_events[evid]
        self.our_zap = damus.zaps.our_zaps[evid]?.first
        self.our_reply = damus.replies.our_reply(evid)
        self.our_quote_repost = damus.quote_reposts.our_events[evid]
        self.objectWillChange.send()
    }
    
    var is_empty: Bool {
        return likes == 0 && boosts == 0 && zaps == 0
    }
    
    var liked: Bool {
        return our_like != nil
    }
    
    var replied: Bool {
        return our_reply != nil
    }
    
    var boosted: Bool {
        return our_boost != nil
    }

    var quoted: Bool {
        return our_quote_repost != nil
    }
}
