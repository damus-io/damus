//
//  ProfilePictureSelector.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI

struct ProfilePictureSelector: View {

    @StateObject var account: CreateAccountModel
    @Binding var profile_image: URL?
    @Binding var image_uploading: Bool
    @State var is_editing = true
    
    @State private var show_camera = false
    @State private var show_library = false
    
    var body: some View {
        let highlight: Highlight = .custom(Color.white, 2.0)
        ZStack {
            EditProfilePictureView(url: $profile_image, fallbackUrl: URL(string: robohash(account.pubkey)), pubkey: account.pubkey, size: 80.0, highlight: highlight)
                .opacity(is_editing ? 0.5 : 1)
            EditProfilePictureControl(account: account, profile_image: $profile_image, image_uploading: $image_uploading)
        }
    }
}

//struct ProfilePictureSelector_Previews: PreviewProvider {
//    static var previews: some View {
//        let model = CreateAccountModel()
//        ProfilePictureSelector(account: model, profile_image: nil)
//    }
//}
