//
//  DamusState.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation

struct DamusState {
    let pool: RelayPool
    let pubkey: String
    let likes: EventCounter
    let boosts: EventCounter
    let image_cache: ImageCache
    let profiles: Profiles
}
