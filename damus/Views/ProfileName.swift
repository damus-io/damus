//
//  ProfileName.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

struct ProfileName: View {
    let pubkey: String
    let profile: Profile?
    let contacts: Contacts
    let prefix: String
    
    let show_friend_confirmed: Bool
    let profiles: Profiles
    
    @State var display_name: String?
    @State var nip05: NIP05?
    
    init(pubkey: String, profile: Profile?, contacts: Contacts, show_friend_confirmed: Bool, profiles: Profiles) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = ""
        self.contacts = contacts
        self.show_friend_confirmed = show_friend_confirmed
        self.profiles = profiles
    }
    
    init(pubkey: String, profile: Profile?, prefix: String, contacts: Contacts, show_friend_confirmed: Bool, profiles: Profiles) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = prefix
        self.contacts = contacts
        self.show_friend_confirmed = show_friend_confirmed
        self.profiles = profiles
    }
    
    var friend_icon: String? {
        if !show_friend_confirmed {
            return nil
        }
        
        if self.contacts.is_friend(self.pubkey) {
            return "person.fill.checkmark"
        }
        
        if self.contacts.is_friend_of_friend(self.pubkey) {
            return "person.fill.and.arrow.left.and.arrow.right"
        }
        
        return nil
    }
    
    var nip05_color: Color {
        contacts.is_friend(pubkey) ? .blue : .yellow
    }
    
    var current_nip05: NIP05? {
        nip05 ?? profiles.is_validated(pubkey)
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Text(prefix + String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
                .font(.body)
                .fontWeight(prefix == "@" ? .none : .bold)
            if let nip05 = current_nip05 {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(nip05_color)
                Text(nip05.host)
                    .foregroundColor(nip05_color)
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
            nip05 = profiles.is_validated(pubkey)
        }
    }
}

/// Profile Name used when displaying an event in the timeline
struct EventProfileName: View {
    let pubkey: String
    let profile: Profile?
    let contacts: Contacts
    let prefix: String
    
    let show_friend_confirmed: Bool
    let profiles: Profiles
    
    @State var display_name: String?
    @State var nip05: NIP05?
    
    let size: EventViewKind
    
    init(pubkey: String, profile: Profile?, contacts: Contacts, show_friend_confirmed: Bool, profiles: Profiles, size: EventViewKind = .normal) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = ""
        self.contacts = contacts
        self.show_friend_confirmed = show_friend_confirmed
        self.size = size
        self.profiles = profiles
    }
    
    init(pubkey: String, profile: Profile?, prefix: String, contacts: Contacts, show_friend_confirmed: Bool, profiles: Profiles, size: EventViewKind = .normal) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = prefix
        self.contacts = contacts
        self.show_friend_confirmed = show_friend_confirmed
        self.size = size
        self.profiles = profiles
    }
    
    var friend_icon: String? {
        if !show_friend_confirmed {
            return nil
        }
        
        if self.contacts.is_friend(self.pubkey) {
            return "person.fill.checkmark"
        }
        
        if self.contacts.is_friend_of_friend(self.pubkey) {
            return "person.fill.and.arrow.left.and.arrow.right"
        }
        
        return nil
    }

    var nip05_color: Color {
        contacts.is_friend(pubkey) ? .blue : .yellow
    }
    
    var current_nip05: NIP05? {
        nip05 ?? profiles.is_validated(pubkey)
    }
   
    var body: some View {
        HStack(spacing: 2) {
            if let real_name = profile?.display_name {
                Text(real_name)
                    .font(.body.weight(.bold))
                    .padding([.trailing], 2)
                
                Text("@" + String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
                    .foregroundColor(.gray)
                    .font(eventviewsize_to_font(size))
            } else {
                Text(String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
                    .font(eventviewsize_to_font(size))
                    .fontWeight(.bold)
            }
            
            if let _ = current_nip05 {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(nip05_color)
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
            nip05 = profiles.is_validated(pubkey)
        }
    }
}
