//
//  ProfileName.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

enum FriendType {
    case friend
    case fof
}

func get_friend_type(contacts: Contacts, pubkey: Pubkey) -> FriendType? {
    if contacts.is_friend_or_self(pubkey) {
        return .friend
    }
    
    if contacts.is_friend_of_friend(pubkey) {
        return .fof
    }
    
    return nil
}

struct ProfileName: View {
    let damus_state: DamusState
    let pubkey: Pubkey
    let prefix: String
    
    let show_nip5_domain: Bool
    
    @State var display_name: DisplayName?
    @State var nip05: NIP05?
    @State var donation: Int?
    
    init(pubkey: Pubkey, prefix: String = "", damus: DamusState, show_nip5_domain: Bool = true) {
        self.pubkey = pubkey
        self.prefix = prefix
        self.damus_state = damus
        self.show_nip5_domain = show_nip5_domain
    }
    
    var friend_type: FriendType? {
        return get_friend_type(contacts: damus_state.contacts, pubkey: self.pubkey)
    }

    @MainActor
    var current_nip05: NIP05? {
        nip05 ?? damus_state.profiles.is_validated(pubkey)
    }
        
    func current_display_name(profile: Profile?) -> DisplayName {
        return display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)
    }
    
    func name_choice(profile: Profile?) -> String {
        return prefix == "@" ? current_display_name(profile: profile).username.truncate(maxLength: 50) : current_display_name(profile: profile).displayName.truncate(maxLength: 50)
    }
    
    func onlyzapper(profile: Profile?) -> Bool {
        guard let profile else {
            return false
        }
        
        return profile.reactions == false
    }
    
    func supporter(profile: Profile?) -> Int? {
        guard let profile,
              let donation = profile.damus_donation,
              donation > 0
        else {
            return nil
        }
        
        return donation
    }
    
    var body: some View {
        let profile_txn = damus_state.profiles.lookup(id: pubkey)
        let profile = profile_txn.unsafeUnownedValue

        HStack(spacing: 2) {
            Text(verbatim: "\(prefix)\(name_choice(profile: profile))")
                .font(.body)
                .fontWeight(prefix == "@" ? .none : .bold)

            if let nip05 = current_nip05 {
                NIP05Badge(nip05: nip05, pubkey: pubkey, contacts: damus_state.contacts, show_domain: show_nip5_domain, profiles: damus_state.profiles)
            }

            if let friend = friend_type, current_nip05 == nil {
                FriendIcon(friend: friend)
            }

            if onlyzapper(profile: profile) {
                Image("zap-hashtag")
                    .frame(width: 14, height: 14)
            }

            if let supporter = supporter(profile: profile) {
                SupporterBadge(percent: supporter)
            }
        }
        .onReceive(handle_notify(.profile_updated)) { update in
            if update.pubkey != pubkey {
                return
            }

            var profile: Profile!
            var profile_txn: NdbTxn<Profile?>!

            switch update {
            case .remote(let pubkey):
                profile_txn = damus_state.profiles.lookup(id: pubkey)
                guard let prof = profile_txn.unsafeUnownedValue else { return }
                profile = prof
            case .manual(_, let prof):
                profile = prof
            }

            let display_name = Profile.displayName(profile: profile, pubkey: pubkey)
            if self.display_name != display_name {
                self.display_name = display_name
            }

            let nip05 = damus_state.profiles.is_validated(pubkey)
            if nip05 != self.nip05 {
                self.nip05 = nip05
            }

            if donation != profile.damus_donation {
                donation = profile.damus_donation
            }
        }
    }
}

struct ProfileName_Previews: PreviewProvider {
    static var previews: some View {
        ProfileName(pubkey: test_damus_state.pubkey, damus: test_damus_state)
    }
}
