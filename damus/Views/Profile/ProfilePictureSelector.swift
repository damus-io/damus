//
//  ProfilePictureSelector.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI

import Combine

class ProfileUploadingViewModel: ObservableObject {
    @Published var isLoading: Bool = false
}

struct ProfilePictureSelector: View {

    let pubkey: String
    var size: CGFloat = 80.0
    var damus_state: DamusState?
    @ObservedObject var viewModel: ProfileUploadingViewModel
    let callback: (URL?) -> Void
    
    @State var profile_image: URL? = nil
    
    var body: some View {
        let highlight: Highlight = .custom(Color.white, 2.0)
        ZStack {
            EditProfilePictureView(url: $profile_image, pubkey: pubkey, size: size, highlight: highlight, damus_state: damus_state)
            EditProfilePictureControl(pubkey: pubkey, profile_image: $profile_image, viewModel: viewModel, callback: callback)
        }
    }
}

struct ProfilePictureSelector_Previews: PreviewProvider {
    static var previews: some View {
        let test_pubkey = "ff48854ac6555fed8e439ebb4fa2d928410e0eef13fa41164ec45aaaa132d846"
        ProfilePictureSelector(pubkey: test_pubkey, viewModel: ProfileUploadingViewModel()) { _ in
            //
        }
    }
}
