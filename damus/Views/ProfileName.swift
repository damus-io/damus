//
//  ProfileName.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

struct ProfileFullName: View {
    let pubkey: String
    let profile: Profile?
    let contacts: Contacts
    
    @State var display_name: String?
    
    var body: some View {
        HStack {
            if let real_name = profile?.display_name {
                Text(real_name)
                    .bold()
                ProfileName(pubkey: pubkey, profile: profile, prefix: "@", contacts: contacts, show_friend_confirmed: true)
                    .font(.footnote)
                    .foregroundColor(.gray)
            } else {
//                ProfileName(pubkey: pubkey, profile: profile, contacts: contacts, show_friend_confirmed: true)
            }
        }
    }
}

struct ProfileName: View {
    let pubkey: String
    let profile: Profile?
    let contacts: Contacts
    let prefix: String
    
    let show_friend_confirmed: Bool
    
    @State var display_name: String?
    
    init(pubkey: String, profile: Profile?, contacts: Contacts, show_friend_confirmed: Bool) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = ""
        self.contacts = contacts
        self.show_friend_confirmed = show_friend_confirmed
    }
    
    init(pubkey: String, profile: Profile?, prefix: String, contacts: Contacts, show_friend_confirmed: Bool) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = prefix
        self.contacts = contacts
        self.show_friend_confirmed = show_friend_confirmed
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
    
    var body: some View {
        HStack {
            
            Text(prefix + String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
                .font(.subheadline)
                .fontWeight(prefix == "@" ? .none : .bold)
            if let frend = friend_icon {
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
    
    @State var display_name: String?
    
    init(pubkey: String, profile: Profile?, contacts: Contacts, show_friend_confirmed: Bool) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = ""
        self.contacts = contacts
        self.show_friend_confirmed = show_friend_confirmed
    }
    
    init(pubkey: String, profile: Profile?, prefix: String, contacts: Contacts, show_friend_confirmed: Bool) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = prefix
        self.contacts = contacts
        self.show_friend_confirmed = show_friend_confirmed
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
    
    var body: some View {
        HStack {
            if let real_name = profile?.display_name {
                Text(real_name)
                    .font(.subheadline.weight(.bold))
                
                Text("@" + String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
                    .foregroundColor(.gray)
                    .font(.subheadline)
            } else {
                Text(String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            
            if let frend = friend_icon {
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
        }
    }
}
