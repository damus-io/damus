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
    @Published var our_tip: NostrEvent?
    @Published var likes: Int
    @Published var boosts: Int
    @Published var tips: Int64
    
    init(likes: Int, boosts: Int, tips: Int64, our_like: NostrEvent?, our_boost: NostrEvent?, our_tip: NostrEvent?) {
        self.likes = likes
        self.boosts = boosts
        self.tips = tips
        self.our_like = our_like
        self.our_boost = our_boost
        self.our_tip = our_tip
    }
    
    var tipped: Bool {
        return our_tip != nil
    }
    
    var liked: Bool {
        return our_like != nil
    }
    
    var boosted: Bool {
        return our_boost != nil
    }
}
