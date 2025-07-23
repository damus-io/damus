//
//  NostrFilter+Hashable.swift
//  damus
//
//  Created by Davide De Rosa on 10/21/23.
//

import Foundation

// FIXME: fine-tune here what's involved in comparing search filters
extension NostrFilter: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hashtag == rhs.hashtag
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hashtag)
    }
}
