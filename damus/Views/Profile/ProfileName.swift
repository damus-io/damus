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
    let profile: Profile?
    let prefix: String
    
    let show_nip5_domain: Bool
    
    @State var display_name: DisplayName?
    @State var nip05: NIP05?
    @State var donation: Int?
    
    init(pubkey: Pubkey, profile: Profile?, prefix: String = "", damus: DamusState, show_nip5_domain: Bool = true) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = prefix
        self.damus_state = damus
        self.show_nip5_domain = show_nip5_domain
    }
    
    var friend_type: FriendType? {
        return get_friend_type(contacts: damus_state.contacts, pubkey: self.pubkey)
    }
    
    var current_nip05: NIP05? {
        nip05 ?? damus_state.profiles.is_validated(pubkey)
    }
        
    var current_display_name: DisplayName {
        return display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)
    }
    
    var name_choice: String {
        return prefix == "@" ? current_display_name.username.truncate(maxLength: 50) : current_display_name.displayName.truncate(maxLength: 50)
    }
    
    var onlyzapper: Bool {
        guard let profile else {
            return false
        }
        
        return profile.reactions == false
    }
    
    var supporter: Int? {
        guard let profile,
              let donation = profile.damus_donation,
              donation > 0
        else {
            return nil
        }
        
        return donation
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Text(verbatim: "\(prefix)\(name_choice)")
                .font(.body)
                .fontWeight(prefix == "@" ? .none : .bold)
            if let nip05 = current_nip05 {
                NIP05Badge(nip05: nip05, pubkey: pubkey, contacts: damus_state.contacts, show_domain: show_nip5_domain, profiles: damus_state.profiles)
            }
            if let friend = friend_type, current_nip05 == nil {
                FriendIcon(friend: friend)
            }
            if onlyzapper {
                Image("zap-hashtag")
                    .frame(width: 14, height: 14)
            }
            if let supporter {
                SupporterBadge(percent: supporter)
            }
        }
        .onReceive(handle_notify(.profile_updated)) { update in
            if update.pubkey != pubkey {
                return
            }
            display_name = Profile.displayName(profile: update.profile, pubkey: pubkey)
            nip05 = damus_state.profiles.is_validated(pubkey)
            donation = profile?.damus_donation
        }
    }
}

struct ProfileName_Previews: PreviewProvider {
    static var previews: some View {
        ProfileName(pubkey:
                        test_damus_state().pubkey, profile: make_test_profile(), damus: test_damus_state())
    }
}
