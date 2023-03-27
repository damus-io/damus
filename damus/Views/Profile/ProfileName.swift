//
//  ProfileName.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

func get_friend_icon(contacts: Contacts, pubkey: String, show_confirmed: Bool) -> String? {
    if !show_confirmed {
        return nil
    }
    
    if contacts.is_friend_or_self(pubkey) {
        return "person.fill.checkmark"
    }
    
    if contacts.is_friend_of_friend(pubkey) {
        return "person.fill.and.arrow.left.and.arrow.right"
    }
    
    return nil
}

struct ProfileName: View {
    let damus_state: DamusState
    let pubkey: String
    let profile: Profile?
    let prefix: String
    
    let show_friend_confirmed: Bool
    let show_nip5_domain: Bool
    
    @State var display_name: DisplayName?
    @State var nip05: NIP05?

    init(pubkey: String, profile: Profile?, damus: DamusState, show_friend_confirmed: Bool, show_nip5_domain: Bool = true) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = ""
        self.show_friend_confirmed = show_friend_confirmed
        self.show_nip5_domain = show_nip5_domain
        self.damus_state = damus
    }
    
    init(pubkey: String, profile: Profile?, prefix: String, damus: DamusState, show_friend_confirmed: Bool, show_nip5_domain: Bool = true) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = prefix
        self.damus_state = damus
        self.show_friend_confirmed = show_friend_confirmed
        self.show_nip5_domain = show_nip5_domain
    }
    
    var friend_icon: String? {
        return get_friend_icon(contacts: damus_state.contacts, pubkey: pubkey, show_confirmed: show_friend_confirmed)
    }
    
    var current_nip05: NIP05? {
        nip05 ?? damus_state.profiles.is_validated(pubkey)
    }
        
    var current_display_name: DisplayName {
        return display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)
    }
    
    var name_choice: String {
        return prefix == "@" ? current_display_name.username : current_display_name.display_name
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Text(verbatim: "\(prefix)\(name_choice)")
                .font(.body)
                .fontWeight(prefix == "@" ? .none : .bold)
            if let nip05 = current_nip05 {
                NIP05Badge(nip05: nip05, pubkey: pubkey, contacts: damus_state.contacts, show_domain: show_nip5_domain, clickable: true)
            }
            if let friend = friend_icon, current_nip05 == nil {
                Image(systemName: friend)
                    .foregroundColor(.gray)
            }
        }
        .onReceive(handle_notify(.profile_updated)) { notif in
            let update = notif.object as! ProfileUpdate
            if update.pubkey != pubkey {
                return
            }
            display_name = Profile.displayName(profile: update.profile, pubkey: pubkey)
            nip05 = damus_state.profiles.is_validated(pubkey)
        }
    }
}

struct ProfileName_Previews: PreviewProvider {
    static var previews: some View {
        ProfileName(pubkey:
                        test_damus_state().pubkey, profile: make_test_profile(), damus: test_damus_state(), show_friend_confirmed: true)
    }
}
