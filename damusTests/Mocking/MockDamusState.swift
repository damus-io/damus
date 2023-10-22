//
//  MockDamusState.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-10-13.
//

import Foundation
@testable import damus

// Generates a test damus state with configurable mock parameters
func generate_test_damus_state(
    mock_profile_info: [Pubkey: Profile]?
) -> DamusState {
    // Create a unique temporary directory
    var tempDir: String!
    do {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true, attributes: nil)
        tempDir = temp.absoluteString
    } catch {
        tempDir = "."
    }

    print("opening \(tempDir!)")
    let ndb = Ndb(path: tempDir)!
    let our_pubkey = test_pubkey
    let pool = RelayPool(ndb: ndb)
    let settings = UserSettingsStore()
    
    let profiles: Profiles = {
        guard let mock_profile_info, let profiles: Profiles = MockProfiles(mocked_profiles: mock_profile_info, ndb: ndb) else {
            return Profiles.init(ndb: ndb)
        }
        return profiles
    }()
    
    let damus = DamusState(pool: pool,
                           keypair: test_keypair,
                           likes: .init(our_pubkey: our_pubkey),
                           boosts: .init(our_pubkey: our_pubkey),
                           contacts: .init(our_pubkey: our_pubkey),
                           profiles: profiles,
                           dms: .init(our_pubkey: our_pubkey),
                           previews: .init(),
                           zaps: .init(our_pubkey: our_pubkey),
                           lnurls: .init(),
                           settings: settings,
                           relay_filters: .init(our_pubkey: our_pubkey),
                           relay_model_cache: .init(),
                           drafts: .init(),
                           events: .init(ndb: ndb),
                           bookmarks: .init(pubkey: our_pubkey),
                           postbox: .init(pool: pool),
                           bootstrap_relays: .init(),
                           replies: .init(our_pubkey: our_pubkey),
                           muted_threads: .init(keypair: test_keypair),
                           wallet: .init(settings: settings),
                           nav: .init(),
                           music: .init(onChange: {_ in }),
                           video: .init(),
                           ndb: ndb)

    return damus
}
