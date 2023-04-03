//
//  BannerImageView.swift
//  damus
//
//  Created by Jason Jōb on 2023-01-10.
//

import SwiftUI
import Kingfisher

struct EditBannerImageView: View {
    
    var damus_state: DamusState
    @ObservedObject var viewModel: ImageUploadingObserver
    let callback: (URL?) -> Void
    let defaultImage = UIImage(named: "profile-banner") ?? UIImage()
    
    @State var banner_image: URL? = nil

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            KFAnimatedImage(get_banner_url(banner: banner_image?.absoluteString, pubkey: damus_state.pubkey, profiles: damus_state.profiles))
                .imageContext(.banner)
                .configure { view in
                    view.framePreloadCount = 3
                }
                .placeholder { _ in
                    Color(uiColor: .secondarySystemBackground)
                }
                .onFailureImage(defaultImage)
            
            EditPictureControl(pubkey: damus_state.pubkey, image_url: $banner_image, uploadObserver: viewModel, callback: callback)
        }
    }
}

struct InnerBannerImageView: View {
    
    let url: URL?
    let defaultImage = UIImage(named: "profile-banner") ?? UIImage()

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            
            if (url != nil) {
                KFAnimatedImage(url)
                    .imageContext(.banner)
                    .configure { view in
                        view.framePreloadCount = 3
                    }
                    .placeholder { _ in
                        Color(uiColor: .secondarySystemBackground)
                    }
                    .onFailureImage(defaultImage)
            } else {
                Image(uiImage: defaultImage).resizable()
            }
        }
    }
}

struct BannerImageView: View {
    let pubkey: String
    let profiles: Profiles
    
    @State var banner: String?
    
    init (pubkey: String, profiles: Profiles, banner: String? = nil) {
        self.pubkey = pubkey
        self.profiles = profiles
        self._banner = State(initialValue: banner)
    }
    
    var body: some View {
        InnerBannerImageView(url: get_banner_url(banner: banner, pubkey: pubkey, profiles: profiles))
            .onReceive(handle_notify(.profile_updated)) { notif in
                let updated = notif.object as! ProfileUpdate

                guard updated.pubkey == self.pubkey else {
                    return
                }
                
                if let bannerImage = updated.profile.banner {
                    self.banner = bannerImage
                }
            }
    }
}

func get_banner_url(banner: String?, pubkey: String, profiles: Profiles) -> URL? {
    let bannerUrlString = banner ?? profiles.lookup(id: pubkey)?.banner ?? ""
    if let url = URL(string: bannerUrlString) {
        return url
    }
    return nil
}

struct BannerImageView_Previews: PreviewProvider {
    static let pubkey = "ca48854ac6555fed8e439ebb4fa2d928410e0eef13fa41164ec45aaaa132d846"
    
    static var previews: some View {
        BannerImageView(
            pubkey: pubkey,
            profiles: make_preview_profiles(pubkey))
    }
}

