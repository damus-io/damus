//
//  ProfileName.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

func ProfileName(pubkey: String, profile: Profile?) -> some View {
    Text(String(Profile.displayName(profile: profile, pubkey: pubkey)))
        //.foregroundColor(hex_to_rgb(pubkey))
        .bold()
}

