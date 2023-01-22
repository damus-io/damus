//
//  BannerImageView.swift
//  damus
//
//  Created by Jason Jōb on 2023-01-10.
//

import SwiftUI
import Kingfisher

struct InnerBannerImageView: View {
    
    let defaultImage = UIImage(named: "profile-banner") ?? UIImage()
    
    @ObservedObject var imageModel: KFImageModel
    
    init(url: URL?) {
        self.imageModel = KFImageModel(
            url: url,
            fallbackUrl: nil,
            maxByteSize: 5000000,
            downsampleSize: CGSize(width: 750, height: 250)
        )
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            
            if (imageModel.url != nil) {
                KFAnimatedImage(imageModel.url)
                    .callbackQueue(.dispatch(.global(qos: .background)))
                    .processingQueue(.dispatch(.global(qos: .background)))
                    .serialize(by: imageModel.serializer)
                    .setProcessor(imageModel.processor)
                    .configure { view in
                        view.framePreloadCount = 1
                    }
                    .placeholder { _ in
                        Color(uiColor: .secondarySystemBackground)
                    }
                    .scaleFactor(UIScreen.main.scale)
                    .loadDiskFileSynchronously()
                    .fade(duration: 0.1)
                    .onFailureImage(defaultImage)
                    .id(imageModel.refreshID)
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

