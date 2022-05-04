//
//  Liked.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation

struct Liked {
    let like: NostrEvent
    let id: String
    let total: Int
}

struct LikeRefs {
    let thread_id: String?
    let like_id: String
}
