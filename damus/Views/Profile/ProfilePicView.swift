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

struct InnerProfilePicView: View {
    let url: URL?
    let fallbackUrl: URL?
    let pubkey: Pubkey
    let size: CGFloat
    let highlight: Highlight
    let disable_animation: Bool

    var Placeholder: some View {
        Circle()
            .frame(width: size, height: size)
            .foregroundColor(DamusColors.mediumGrey)
            .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
            .padding(2)
    }

    var body: some View {
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
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
    }
}


struct ProfilePicView: View {
    let pubkey: Pubkey
    let size: CGFloat
    let highlight: Highlight
    let profiles: Profiles
    let disable_animation: Bool
    let zappability_indicator: Bool
    
    @State var picture: String?
    
    init(pubkey: Pubkey, size: CGFloat, highlight: Highlight, profiles: Profiles, disable_animation: Bool, picture: String? = nil, show_zappability: Bool? = nil) {
        self.pubkey = pubkey
        self.profiles = profiles
        self.size = size
        self.highlight = highlight
        self._picture = State(initialValue: picture)
        self.disable_animation = disable_animation
        self.zappability_indicator = show_zappability ?? false
    }
    
    func get_lnurl() -> String? {
        return profiles.lookup_with_timestamp(pubkey).unsafeUnownedValue?.lnurl
    }
    
    var body: some View {
        ZStack (alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
            InnerProfilePicView(url: get_profile_url(picture: picture, pubkey: pubkey, profiles: profiles), fallbackUrl: URL(string: robohash(pubkey)), pubkey: pubkey, size: size, highlight: highlight, disable_animation: disable_animation)
                .onReceive(handle_notify(.profile_updated)) { updated in
                    guard updated.pubkey == self.pubkey else {
                        return
                    }
                    
                    switch updated {
                        case .manual(_, let profile):
                            if let pic = profile.picture {
                                self.picture = pic
                            }
                        case .remote(pubkey: let pk):
                            let profile_txn = profiles.lookup(id: pk)
                            let profile = profile_txn.unsafeUnownedValue
                            if let pic = profile?.picture {
                                self.picture = pic
                            }
                    }
                }
            
            if self.zappability_indicator, let lnurl = self.get_lnurl(), lnurl != "" {
                Image("zap.fill")
                    .resizable()
                    .frame(
                        width: size * 0.24,
                        height: size * 0.24
                    )
                    .padding(size * 0.04)
                    .foregroundColor(.white)
                    .background(Color.orange)
                    .clipShape(Circle())
            }
        }
    }
}

func get_profile_url(picture: String?, pubkey: Pubkey, profiles: Profiles) -> URL {
    let pic = picture ?? profiles.lookup(id: pubkey).map({ $0?.picture }).value ?? robohash(pubkey)
    if let url = URL(string: pic) {
        return url
    }
    return URL(string: robohash(pubkey))!
}

func make_preview_profiles(_ pubkey: Pubkey) -> Profiles {
    let profiles = Profiles(ndb: test_damus_state.ndb)
    let picture = "http://cdn.jb55.com/img/red-me.jpg"
    let profile = Profile(name: "jb55", display_name: "William Casarin", about: "It's me", picture: picture, banner: "", website: "https://jb55.com", lud06: nil, lud16: nil, nip05: "jb55.com", damus_donation: nil)
    //let ts_profile = TimestampedProfile(profile: profile, timestamp: 0, event: test_note)
    //profiles.add(id: pubkey, profile: ts_profile)
    return profiles
}

struct ProfilePicView_Previews: PreviewProvider {
    static let pubkey = test_note.pubkey

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
