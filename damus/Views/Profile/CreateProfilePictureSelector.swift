//
//  ProfilePictureSelector.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI

struct CreateProfilePictureSelector: View {

    let pubkey: String
    
    @Binding var profile_image: URL?
    @Binding var image_uploading: Bool
    
    var body: some View {
        let highlight: Highlight = .custom(Color.white, 2.0)
        ZStack {
            EditProfilePictureView(url: $profile_image, fallbackUrl: URL(string: robohash(pubkey)), pubkey: pubkey, size: 80.0, highlight: highlight)
                .opacity(0.5)
            EditProfilePictureControl(pubkey: pubkey, profile_image: $profile_image, image_uploading: $image_uploading)
        }
    }
}

struct CreateProfilePictureSelectorishgh: View {

    let pubkey: String
    let handler: (MediaUpload) -> URL?
    
    var body: some View {
        let highlight: Highlight = .custom(Color.white, 2.0)
        ZStack {
            EditProfilePictureView(url: $profile_image, fallbackUrl: URL(string: robohash(pubkey)), pubkey: pubkey, size: 80.0, highlight: highlight)
                .opacity(0.5)
            EditProfilePictureControl(pubkey: pubkey, profile_image: $profile_image, image_uploading: $image_uploading)
        }
    }
}

struct EditProfilePictureSelector: View {
    
    let pubkey: String

    @Binding var image_uploading: Bool
    @Binding var profile_image: String?

    var body: some View {
        let highlight: Highlight = .custom(Color.white, 2.0)
        ZStack {
//            let profile_url = URL(string: $profile_image.wrappedValue ?? "")
//            EditProfilePictureView(url: profile_url, fallbackUrl: URL(string: robohash(account.pubkey)), pubkey: account.pubkey, size: 80.0, highlight: highlight)
//                .opacity(0.5)
            EditProfilePictureControl(pub: account, profile_image: $profile_image.asOptionalURL, image_uploading: $image_uploading)
        }
    }
    
    extension Binding where Value == String? {
        var asOptionalURL: Binding<URL?> {
            Binding<URL?>(
                get: { self.wrappedValue.flatMap(URL.init(string:)) },
                set: { newValue in
                    self.wrappedValue = newValue?.absoluteString
                }
            )
        }
    }
}

//struct ProfilePictureSelector_Previews: PreviewProvider {
//    static var previews: some View {
//        let model = CreateAccountModel()
//        ProfilePictureSelector(account: model, profile_image: nil)
//    }
//}
