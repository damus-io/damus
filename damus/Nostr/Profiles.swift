//
//  Profiles.swift
//  damus
//
//  Created by William Casarin on 2022-04-17.
//

import Foundation
import UIKit
import Combine


class Profiles {
    var profiles: [String: TimestampedProfile] = [:]
    
    func add(id: String, profile: TimestampedProfile) {
        profiles[id] = profile
    }
    
    func lookup(id: String) -> Profile? {
        return profiles[id]?.profile
    }
    
    func lookup_with_timestamp(id: String) -> TimestampedProfile? {
        return profiles[id]
    }
}
