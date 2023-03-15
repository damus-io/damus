//
//  EventProfileName.swift
//  damus
//
//  Created by William Casarin on 2023-03-14.
//

import SwiftUI

/// Profile Name used when displaying an event in the timeline
struct EventProfileName: View {
    let damus_state: DamusState
    let pubkey: String
    let profile: Profile?
    let prefix: String
    
    let show_friend_confirmed: Bool
    
    @State var display_name: DisplayName?
    @State var nip05: NIP05?
    
    let size: EventViewKind
    
    init(pubkey: String, profile: Profile?, damus: DamusState, show_friend_confirmed: Bool, size: EventViewKind = .normal) {
        self.damus_state = damus
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = ""
        self.show_friend_confirmed = show_friend_confirmed
        self.size = size
    }
    
    init(pubkey: String, profile: Profile?, prefix: String, damus: DamusState, show_friend_confirmed: Bool, size: EventViewKind = .normal) {
        self.damus_state = damus
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = prefix
        self.show_friend_confirmed = show_friend_confirmed
        self.size = size
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
   
    var body: some View {
        HStack(spacing: 2) {
            switch current_display_name {
            case .one(let one):
                Text(one)
                    .font(.body.weight(.bold))
                
            case .both(let both):
                Text(both.display_name)
                    .font(.body.weight(.bold))
                
                Text(verbatim: "@\(both.username)")
                    .foregroundColor(.gray)
                    .font(eventviewsize_to_font(size))
            }
            
            if let nip05 = current_nip05 {
                NIP05Badge(nip05: nip05, pubkey: pubkey, contacts: damus_state.contacts, show_domain: false, clickable: false)
            }
            
            if let frend = friend_icon, current_nip05 == nil {
                Label("", systemImage: frend)
                    .foregroundColor(.gray)
                    .font(.footnote)
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


struct EventProfileName_Previews: PreviewProvider {
    static var previews: some View {
        EventProfileName(pubkey: "pk", profile: nil, damus: test_damus_state(), show_friend_confirmed: true)
    }
}
