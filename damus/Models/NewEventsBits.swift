//
//  NewEventsBits.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation

struct NewEventsBits: OptionSet {
    let rawValue: Int
    
    static let home = NewEventsBits(rawValue: 1 << 0)
    static let zaps = NewEventsBits(rawValue: 1 << 1)
    static let mentions = NewEventsBits(rawValue: 1 << 2)
    static let reposts = NewEventsBits(rawValue: 1 << 3)
    static let likes = NewEventsBits(rawValue: 1 << 4)
    static let search = NewEventsBits(rawValue: 1 << 5)
    static let dms = NewEventsBits(rawValue: 1 << 6)
    
    static let all = NewEventsBits(rawValue: 0xFFFFFFFF)
    static let notifications: NewEventsBits = [.zaps, .likes, .reposts, .mentions]
}
