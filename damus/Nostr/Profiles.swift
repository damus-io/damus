//
//  Profiles.swift
//  damus
//
//  Created by William Casarin on 2022-04-17.
//

import Foundation
import UIKit


class Profiles {
    
    /// This queue is used to synchronize access to the profiles dictionary, which
    /// prevents data races from crashing the app.
    private var queue = DispatchQueue(label: "io.damus.profiles",
                                      qos: .userInteractive,
                                      attributes: .concurrent)
    
    private var profiles: [String: TimestampedProfile] = [:]
    var validated: [String: NIP05] = [:]
    var nip05_pubkey: [String: String] = [:]
    var zappers: [String: String] = [:]
    
    func is_validated(_ pk: String) -> NIP05? {
        return validated[pk]
    }
    
    func enumerated() -> EnumeratedSequence<[String: TimestampedProfile]> {
        return queue.sync {
            return profiles.enumerated()
        }
    }
    
    func lookup_zapper(pubkey: String) -> String? {
        if let zapper = zappers[pubkey] {
            return zapper
        }
        
        return nil
    }
    
    func add(id: String, profile: TimestampedProfile) {
        queue.async(flags: .barrier) {
            self.profiles[id] = profile
        }
    }
    
    func lookup(id: String) -> Profile? {
        queue.sync {
            return profiles[id]?.profile
        }
    }
    
    func lookup_with_timestamp(id: String) -> TimestampedProfile? {
        queue.sync {
            return profiles[id]
        }
    }
}


func invalidate_zapper_cache(pubkey: String, profiles: Profiles, lnurl: LNUrls) {
    profiles.zappers.removeValue(forKey: pubkey)
    lnurl.endpoints.removeValue(forKey: pubkey)
}
