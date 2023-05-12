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
    @NSManaged var last_update: Date?
}
