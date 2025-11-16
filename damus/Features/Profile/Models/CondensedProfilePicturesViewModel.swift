//
//  CondensedProfilePicturesViewModel.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-09-15.
//
import Combine
import Foundation

class CondensedProfilePicturesViewModel: ObservableObject {
    let state: DamusState
    let pubkeys: [Pubkey]
    let maxPictures: Int
    var shownPubkeys: [Pubkey] {
        return Array(pubkeys.prefix(maxPictures))
    }
    var loadingTask: Task<Void, Never>? = nil
    
    init(state: DamusState, pubkeys: [Pubkey], maxPictures: Int) {
        self.state = state
        self.pubkeys = pubkeys
        self.maxPictures = min(maxPictures, pubkeys.count)
    }
}
