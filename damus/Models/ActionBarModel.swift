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
    @Published var likes: Int
    
    init(likes: Int, our_like: NostrEvent?, our_boost: NostrEvent?) {
        self.likes = likes
        self.our_like = our_like
        self.our_boost = our_boost
    }
    
    var liked: Bool {
        return our_like != nil
    }
    
    var boosted: Bool {
        return our_boost != nil
    }
}
