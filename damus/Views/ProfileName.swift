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
    
    @State var display_name: String?
    
    var body: some View {
        HStack {
            if let real_name = profile?.display_name {
                Text(real_name)
                    .bold()
                ProfileName(pubkey: pubkey, profile: profile, prefix: "@")
                    .font(.footnote)
                    .foregroundColor(.gray)
            } else {
                ProfileName(pubkey: pubkey, profile: profile)
            }
        }
    }
}

struct ProfileName: View {
    let pubkey: String
    let profile: Profile?
    let prefix: String
    
    @State var display_name: String?
    
    init(pubkey: String, profile: Profile?) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = ""
    }
    
    init(pubkey: String, profile: Profile?, prefix: String) {
        self.pubkey = pubkey
        self.profile = profile
        self.prefix = prefix
    }
    
    var body: some View {
        HStack {
            Text(prefix + String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
                //.foregroundColor(hex_to_rgb(pubkey))
                .fontWeight(prefix == "@" ? .none : .bold)
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


