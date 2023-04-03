//
//  EditProfilePictureView.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI
import Kingfisher
import Combine

struct EditProfilePictureView: View {
    
    @State var profile_url: URL?
    
    let pubkey: String
    var damus_state: DamusState?
    var size: CGFloat = 80.0
    let highlight: Highlight = .custom(Color.white, 2.0)
    @ObservedObject var uploadObserver: ImageUploadingObserver
    let callback: (URL?) -> Void

    var PlaceholderColor: Color {
        return id_to_color(pubkey)
    }

    var Placeholder: some View {
        PlaceholderColor
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
            .padding(2)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
    
            KFAnimatedImage(get_profile_url())
                .imageContext(.pfp)
                .cancelOnDisappear(true)
                .configure { view in
                    view.framePreloadCount = 3
                }
                .placeholder { _ in
                    Placeholder
                }
                .scaledToFill()
    
            EditPictureControl(pubkey: pubkey, image_url: $profile_url, uploadObserver: uploadObserver, callback: callback)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
    }
    
    private func get_profile_url() -> URL? {
        if let profile_url {
            return profile_url
        } else if let state = damus_state, let picture = state.profiles.lookup(id: pubkey)?.picture {
            return URL(string: picture)
        } else {
            return profile_url ?? URL(string: robohash(pubkey))
        }
    }
}

struct ProfilePictureSelector_Previews: PreviewProvider {
    static var previews: some View {
        let test_pubkey = "ff48854ac6555fed8e439ebb4fa2d928410e0eef13fa41164ec45aaaa132d846"
        EditProfilePictureView(pubkey: test_pubkey, uploadObserver: ImageUploadingObserver()) { _ in
            //
        }
    }
}
