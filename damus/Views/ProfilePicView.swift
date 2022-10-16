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

struct ProfilePicView: View {
    let pubkey: String
    let size: CGFloat
    let highlight: Highlight
    let profiles: Profiles
    
    @State var picture: String? = nil
    
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
    
    var MainContent: some View {
        Group {
            let pic = picture ?? profiles.lookup(id: pubkey)?.picture ?? robohash(pubkey)
            let url = URL(string: pic)
            let processor = /*DownsamplingImageProcessor(size: CGSize(width: size, height: size))
                         |>*/ ResizingImageProcessor(referenceSize: CGSize(width: size, height: size))
                         |> RoundCornerImageProcessor(cornerRadius: 20)
            KFImage.url(url)
                .placeholder { _ in
                    Placeholder
                }
                .setProcessor(processor)
                .scaleFactor(UIScreen.main.scale)
                .loadDiskFileSynchronously()
                .fade(duration: 0.1)
        }
    }
    
    var body: some View {
        MainContent
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

func make_preview_profiles(_ pubkey: String) -> Profiles {
    let profiles = Profiles()
    let picture = "http://cdn.jb55.com/img/red-me.jpg"
    let profile = Profile(name: "jb55", display_name: "William Casarin", about: "It's me", picture: picture)
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
