//
//  ProfilePictureSelector.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI

struct ProfilePictureSelector: View {

    let pubkey: String
    var size: CGFloat = 80.0
    let callback: (URL?) -> Void

    @State var profile_image: URL?
    
    var body: some View {
        let highlight: Highlight = .custom(Color.white, 2.0)
        ZStack {
            EditProfilePictureView(url: $profile_image, fallbackUrl: URL(string: robohash(pubkey)), pubkey: pubkey, size: size, highlight: highlight)
            EditProfilePictureControl(pubkey: pubkey, profile_image: $profile_image, callback: callback)
        }
    }
}
