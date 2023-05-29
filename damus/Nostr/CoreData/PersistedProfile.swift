//
//  PersistedProfile.swift
//  damus
//
//  Created by Bryan Montz on 4/30/23.
//

import Foundation
import CoreData

@objc(PersistedProfile)
final class PersistedProfile: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var name: String?
    @NSManaged var display_name: String?
    @NSManaged var about: String?
    @NSManaged var picture: String?
    @NSManaged var banner: String?
    @NSManaged var website: String?
    @NSManaged var lud06: String?
    @NSManaged var lud16: String?
    @NSManaged var nip05: String?
    @NSManaged var damus_donation: Int16
    @NSManaged var last_update: Date?       // The date that the profile was last updated by the user
    @NSManaged var network_pull_date: Date? // The date we got this profile from a relay (for staleness checking)
    
    func copyValues(from profile: Profile) {
        name = profile.name
        display_name = profile.display_name
        about = profile.about
        picture = profile.picture
        banner = profile.banner
        website = profile.website
        lud06 = profile.lud06
        lud16 = profile.lud16
        nip05 = profile.nip05
        damus_donation = profile.damus_donation != nil ? Int16(profile.damus_donation!) : 0
    }
}
