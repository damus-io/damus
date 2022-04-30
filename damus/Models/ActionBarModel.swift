//
//  ActionBarModel.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation


class ActionBarModel: ObservableObject {
    @Published var our_like_event: NostrEvent? = nil
    @Published var our_boost_event: NostrEvent? = nil
    
    var liked: Bool {
        return our_like_event != nil
    }
    
    var boosted: Bool {
        return our_boost_event != nil
    }
}
