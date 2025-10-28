//
//  MockDamusState.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-10-13.
//

import Foundation
@testable import damus
import EmojiPicker

// Generates a test damus state with configurable mock parameters
func generate_test_damus_state(
    mock_profile_info: [Pubkey: Profile]?,
    home: HomeModel? = nil,
    addNdbToRelayPool: Bool = true
) -> DamusState {
    // Create a unique temporary directory
    let ndb = Ndb.test
    let our_pubkey = test_pubkey
    let settings = UserSettingsStore()
    
    let profiles: Profiles = {
        guard let mock_profile_info, let profiles: Profiles = MockProfiles(mocked_profiles: mock_profile_info, ndb: ndb) else {
            return Profiles.init(ndb: ndb)
        }
        return profiles
    }()
    
    let mutelist_manager = MutelistManager(user_keypair: test_keypair)
    let damus = DamusState(keypair: test_keypair,
                           likes: .init(our_pubkey: our_pubkey),
                           boosts: .init(our_pubkey: our_pubkey),
                           contacts: .init(our_pubkey: our_pubkey),
                           contactCards: ContactCardManagerMock(),
                           mutelist_manager: mutelist_manager,
                           profiles: profiles,
                           dms: home?.dms ?? .init(our_pubkey: our_pubkey),
                           previews: .init(),
                           zaps: .init(our_pubkey: our_pubkey),
                           lnurls: .init(),
                           settings: settings,
                           relay_filters: .init(our_pubkey: our_pubkey),
                           relay_model_cache: .init(),
                           drafts: .init(),
                           events: .init(ndb: ndb),
                           bookmarks: .init(pubkey: our_pubkey),
                           replies: .init(our_pubkey: our_pubkey),
                           wallet: .init(settings: settings),
                           nav: .init(),
                           music: .init(onChange: {_ in }),
                           video: .init(),
                           ndb: ndb,
                           quote_reposts: .init(our_pubkey: our_pubkey),
                           emoji_provider: DefaultEmojiProvider(showAllVariations: false),
                           favicon_cache: .init(),
                           addNdbToRelayPool: addNdbToRelayPool
    )
    
    home?.damus_state = damus

    return damus
}
