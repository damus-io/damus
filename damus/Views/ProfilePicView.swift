//
//  ProfilePicView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI
import Kingfisher

let PFP_SIZE: CGFloat = 52.0

func id_to_color(_ id: String) -> Color {
    return hex_to_rgb(id)
}

func highlight_color(_ h: Highlight) -> Color {
    switch h {
    case .main: return Color.red
    case .reply: return Color.black
    case .none: return Color.black
    case .custom(let c, _): return c
    }
}

func pfp_line_width(_ h: Highlight) -> CGFloat {
    switch h {
    case .reply: return 0
    case .none: return 0
    case .main: return 3
    case .custom(_, let lw): return CGFloat(lw)
    }
}

struct InnerProfilePicView: View {
    let url: URL?
    let pubkey: String
    let size: CGFloat
    let highlight: Highlight

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
        Group {
            KFAnimatedImage(url)
                .callbackQueue(.dispatch(.global(qos: .background)))
                .processingQueue(.dispatch(.global(qos: .background)))
                .appendProcessor(LargeImageProcessor())
                .configure { view in
                    view.framePreloadCount = 1
                }
                .placeholder { _ in
                    Placeholder
                }
                .scaleFactor(UIScreen.main.scale)
                .loadDiskFileSynchronously()
                .fade(duration: 0.1)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
    }
}

struct ProfilePicView: View {
    let pubkey: String
    let size: CGFloat
    let highlight: Highlight
    let profiles: Profiles
    
    @State var picture: String?
    
    init (pubkey: String, size: CGFloat, highlight: Highlight, profiles: Profiles, picture: String? = nil) {
        self.pubkey = pubkey
        self.profiles = profiles
        self.size = size
        self.highlight = highlight
        self._picture = State(initialValue: picture)
    }
    
    var body: some View {
        InnerProfilePicView(url: get_profile_url(picture: picture, pubkey: pubkey, profiles: profiles), pubkey: pubkey, size: size, highlight: highlight)
            .onReceive(handle_notify(.profile_updated)) { notif in
                let updated = notif.object as! ProfileUpdate

                guard updated.pubkey == self.pubkey else {
                    return
                }
                
                if let pic = updated.profile.picture {
                    self.picture = pic
                }
            }
    }
}

struct LargeImageProcessor: ImageProcessor {
    
    let identifier: String = "com.damus.largeimageprocessor"
    let maxSize: Int = 1000000
    let downsampleSize = CGSize(width: 200, height: 200)
    
    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        
        switch item {
        case .image(let image):
            guard let data = image.kf.data(format: .unknown) else {
                return nil
            }
            
            if data.count > maxSize {
                return KingfisherWrapper.downsampledImage(data: data, to: downsampleSize, scale: options.scaleFactor)
            }
            return image
        case .data(let data):
            if data.count > maxSize {
                return KingfisherWrapper.downsampledImage(data: data, to: downsampleSize, scale: options.scaleFactor)
            }
            return KFCrossPlatformImage(data: data)
        }
    }
}

func get_profile_url(picture: String?, pubkey: String, profiles: Profiles) -> URL {
    let pic = picture ?? profiles.lookup(id: pubkey)?.picture ?? robohash(pubkey)
    if let url = URL(string: pic) {
        return url
    }
    return URL(string: robohash(pubkey))!
}

func make_preview_profiles(_ pubkey: String) -> Profiles {
    let profiles = Profiles()
    let picture = "http://cdn.jb55.com/img/red-me.jpg"
    let profile = Profile(name: "jb55", display_name: "William Casarin", about: "It's me", picture: picture, website: "https://jb55.com", lud06: nil, lud16: nil, nip05: "jb55.com")
    let ts_profile = TimestampedProfile(profile: profile, timestamp: 0)
    profiles.add(id: pubkey, profile: ts_profile)
    return profiles
}

struct ProfilePicView_Previews: PreviewProvider {
    static let pubkey = "ca48854ac6555fed8e439ebb4fa2d928410e0eef13fa41164ec45aaaa132d846"
    
    static var previews: some View {
        ProfilePicView(
            pubkey: pubkey,
            size: 100,
            highlight: .none,
            profiles: make_preview_profiles(pubkey))
    }
}

func hex_to_rgb(_ hex: String) -> Color {
    guard hex.count >= 6 else {
        return Color.white
    }
    
    let arr = Array(hex.utf8)
    var rgb: [UInt8] = []
    var i: Int = arr.count - 12
    
    while i < arr.count {
        let cs1 = arr[i]
        let cs2 = arr[i+1]
        
        guard let c1 = char_to_hex(cs1) else {
            return Color.black
        }

        guard let c2 = char_to_hex(cs2) else {
            return Color.black
        }
        
        rgb.append((c1 << 4) | c2)
        i += 2
    }

    return Color.init(
        .sRGB,
        red: Double(rgb[0]) / 255,
        green: Double(rgb[1]) / 255,
        blue:  Double(rgb[2]) / 255,
        opacity: 1
    )
}
