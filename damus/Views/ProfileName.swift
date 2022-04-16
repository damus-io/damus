//
//  ProfileName.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

func ProfileName(pubkey: String, profile: Profile?) -> some View {
    Text(String(profile?.name ?? String(pubkey.prefix(16))))
        .bold()
        .onTapGesture {
            UIPasteboard.general.string = pubkey
        }
}

