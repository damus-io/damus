//
//  MockProfiles.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-10-13.
//

import Foundation
@testable import damus

// A Mockable `Profiles` class that can be used for testing.
// Note: Not all methods are mocked. You might need to implement a method depending on the test you are writing.
class MockProfiles: Profiles {
    var mocked_profiles: [Pubkey: Profile] = [:]
    var ndb: Ndb
    
    init?(mocked_profiles: [Pubkey : Profile], ndb: Ndb) {
        self.mocked_profiles = mocked_profiles
        self.ndb = ndb
        super.init(ndb: ndb)
    }

    override func lookup(id: Pubkey) -> NdbTxn<Profile?> {
        return NdbTxn(ndb: self.ndb) { txn in
            return self.mocked_profiles[id]
        }
    }
}
