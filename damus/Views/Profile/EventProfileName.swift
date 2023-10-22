//
//  EventProfileName.swift
//  damus
//
//  Created by William Casarin on 2023-03-14.
//

import SwiftUI

/// Profile Name used when displaying an event in the timeline
@MainActor
struct EventProfileName: View {
    let damus_state: DamusState
    let pubkey: Pubkey

    @State var display_name: DisplayName?
    @State var nip05: NIP05?
    @State var donation: Int?
    
    let size: EventViewKind
    
    init(pubkey: Pubkey, damus: DamusState, size: EventViewKind = .normal) {
        self.damus_state = damus
        self.pubkey = pubkey
        self.size = size
        let donation = damus.ndb.lookup_profile(pubkey).map({ p in p?.profile?.damus_donation }).value
        self._donation = State(wrappedValue: donation)
    }
    
    var friend_type: FriendType? {
        return get_friend_type(contacts: damus_state.contacts, pubkey: self.pubkey)
    }
    
    var current_nip05: NIP05? {
        nip05 ?? damus_state.profiles.is_validated(pubkey)
    }
    
    func current_display_name(_ profile: Profile?) -> DisplayName {
        return display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)
    }
    
    func onlyzapper(_ profile: Profile?) -> Bool {
        guard let profile else {
            return false
        }
        
        return profile.reactions == false
    }
    
    var supporter: Int? {
        guard let donation, donation > 0
        else {
            return nil
        }
        
        return donation
    }

    var body: some View {
        let profile_txn = damus_state.profiles.lookup(id: pubkey)
        let profile = profile_txn.unsafeUnownedValue
        HStack(spacing: 2) {
            switch current_display_name(profile) {
            case .one(let one):
                Text(one)
                    .font(.body.weight(.bold))
                
            case .both(username: let username, displayName: let displayName):
                    HStack(spacing: 6) {
                        Text(verbatim: displayName)
                            .font(.body.weight(.bold))
                        
                        Text(verbatim: "@\(username)")
                            .foregroundColor(.gray)
                            .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                    }
            }
            
            /*
            if let nip05 = current_nip05 {
                NIP05Badge(nip05: nip05, pubkey: pubkey, contacts: damus_state.contacts, show_domain: false, clickable: false)
            }
             */
            
             
            if let frend = friend_type {
                FriendIcon(friend: frend)
            }
            
            if onlyzapper(profile) {
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

            let profile_txn = damus_state.profiles.lookup(id: update.pubkey)
            guard let profile = profile_txn.unsafeUnownedValue else { return }

            let display_name = Profile.displayName(profile: profile, pubkey: pubkey)
            if display_name != self.display_name {
                self.display_name = display_name
            }

            let nip05 = damus_state.profiles.is_validated(pubkey)

            if self.nip05 != nip05 {
                self.nip05 = nip05
            }

            if self.donation != profile.damus_donation {
                donation = profile.damus_donation
            }
        }
    }
}


struct EventProfileName_Previews: PreviewProvider {
    static var previews: some View {
        EventProfileName(pubkey: test_note.pubkey, damus: test_damus_state)
    }
}
