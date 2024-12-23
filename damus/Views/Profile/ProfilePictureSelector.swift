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
    
    let pubkey: Pubkey
    var damus_state: DamusState?
    var size: CGFloat = 80.0
    let highlight: Highlight = .custom(Color.white, 2.0)
    @ObservedObject var uploadObserver: ImageUploadingObserver
    let callback: (URL?) -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
    
            KFAnimatedImage(get_profile_url())
                .imageContext(.pfp, disable_animation: damus_state?.settings.disable_animation == true)
                .cancelOnDisappear(true)
                .configure { view in
                    view.framePreloadCount = 3
                }
                .scaledToFill()
                .kfClickable()
    
            EditPictureControl(
                uploader: damus_state?.settings.default_media_uploader ?? .nostrBuild,
                context: .profile_picture,
                keypair: damus_state?.keypair,
                pubkey: pubkey,
                current_image_url: $profile_url,
                upload_observer: uploadObserver,
                callback: callback
            )
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
    }
    
    private func get_profile_url() -> URL? {
        if let profile_url {
            return profile_url
        } else if let state = damus_state,
                  let picture = state.profiles.lookup(id: pubkey)?.map({ pr in pr?.picture }).value {
            return URL(string: picture)
        } else {
            return profile_url ?? URL(string: robohash(pubkey))
        }
    }
}

struct ProfilePictureSelector_Previews: PreviewProvider {
    static var previews: some View {
        EditProfilePictureView(pubkey: test_pubkey, uploadObserver: ImageUploadingObserver()) { _ in
            //
        }
    }
}
