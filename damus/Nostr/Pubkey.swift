//
//  Pubkey.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

// prepare a more gradual transition to the ndb branch
typealias FollowRef = ReferencedId
typealias Pubkey = String
typealias NoteId = String
typealias Privkey = String

extension String {
    // Id constructors
    init?(hex: String) {
        self = hex
    }

    static var empty: String {
        return ""
    }

    func hex() -> String {
        return self
    }
}
