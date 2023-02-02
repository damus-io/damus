//
//  ProfilePictureSelector.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI

struct ProfilePictureSelector: View {
    let pubkey: String
    
    var body: some View {
        let highlight: Highlight = .custom(Color.white, 2.0)
        ZStack {
            ProfilePicView(pubkey: pubkey, size: 80.0, highlight: highlight, profiles: Profiles(), contacts: Contacts())
        }
    }
}

struct ProfilePictureSelector_Previews: PreviewProvider {
    static var previews: some View {
        let test_pubkey = "ff48854ac6555fed8e439ebb4fa2d928410e0eef13fa41164ec45aaaa132d846"
        ProfilePictureSelector(pubkey: test_pubkey)
    }
}
