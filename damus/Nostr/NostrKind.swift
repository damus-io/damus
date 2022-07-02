//
//  NostrKind.swift
//  damus
//
//  Created by William Casarin on 2022-04-27.
//

import Foundation


enum NostrKind: Int {
    case metadata = 0
    case text = 1
    case contacts = 3
    case dm = 4
    case delete = 5
    case boost = 6
    case like = 7
}
