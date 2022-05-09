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
    
    @State var display_name: String?
    
    var body: some View {
        Text(String(display_name ?? Profile.displayName(profile: profile, pubkey: pubkey)))
            //.foregroundColor(hex_to_rgb(pubkey))
            .bold()
            .onReceive(handle_notify(.profile_updated)) { notif in
                let update = notif.object as! ProfileUpdate
                if update.pubkey != pubkey {
                    return
                }
                display_name = Profile.displayName(profile: update.profile, pubkey: pubkey)
            }
    }
}


