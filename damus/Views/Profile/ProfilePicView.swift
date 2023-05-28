//
//  ProfilePicView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI
import Kingfisher

let PFP_SIZE: CGFloat = 52.0

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

struct EditProfilePictureView: View {
    
    @Binding var url: URL?
    
    let pubkey: String
    let size: CGFloat
    let highlight: Highlight
    
    var damus_state: DamusState?

    var Placeholder: some View {
        Circle()
            .frame(width: size, height: size)
            .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
            .padding(2)
    }
    
    var disable_animation: Bool {
        damus_state?.settings.disable_animation ?? false
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
    
            KFAnimatedImage(get_profile_url())
                .imageContext(.pfp, disable_animation: disable_animation)
                .cancelOnDisappear(true)
                .configure { view in
                    view.framePreloadCount = 3
                }
                .placeholder { _ in
                    Placeholder
                }
                .scaledToFill()
                .opacity(0.5)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
    }
    
    private func get_profile_url() -> URL? {
        if let url {
            return url
        } else if let state = damus_state, let picture = state.profiles.lookup(id: pubkey)?.picture {
            return URL(string: picture)
        } else {
            return url ?? URL(string: robohash(pubkey))
        }
    }
}

struct InnerProfilePicView: View {
    let url: URL?
    let fallbackUrl: URL?
    let pubkey: String
    let size: CGFloat
    let highlight: Highlight
    let disable_animation: Bool

    var Placeholder: some View {
        Circle()
            .frame(width: size, height: size)
            .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
            .padding(2)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
    
            KFAnimatedImage(url)
                .imageContext(.pfp, disable_animation: disable_animation)
                .onFailure(fallbackUrl: fallbackUrl, cacheKey: url?.absoluteString)
                .cancelOnDisappear(true)
                .configure { view in
                    view.framePreloadCount = 3
                }
                .placeholder { _ in
                    Placeholder
                }
                .scaledToFill()
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
    let disable_animation: Bool
    
    @State var picture: String?
    
    init (pubkey: String, size: CGFloat, highlight: Highlight, profiles: Profiles, disable_animation: Bool, picture: String? = nil) {
        self.pubkey = pubkey
        self.profiles = profiles
        self.size = size
        self.highlight = highlight
        self._picture = State(initialValue: picture)
        self.disable_animation = disable_animation
    }
    
    var body: some View {
        InnerProfilePicView(url: get_profile_url(picture: picture, pubkey: pubkey, profiles: profiles), fallbackUrl: URL(string: robohash(pubkey)), pubkey: pubkey, size: size, highlight: highlight, disable_animation: disable_animation)
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
    let profile = Profile(name: "jb55", display_name: "William Casarin", about: "It's me", picture: picture, banner: "", website: "https://jb55.com", lud06: nil, lud16: nil, nip05: "jb55.com", damus_donation: nil)
    let ts_profile = TimestampedProfile(profile: profile, timestamp: 0, event: test_event)
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
            profiles: make_preview_profiles(pubkey),
            disable_animation: false
        )
    }
}
