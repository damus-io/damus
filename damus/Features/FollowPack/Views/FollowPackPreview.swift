//
//  FollowPackPreview.swift
//  damus
//
//  Created by eric on 4/30/25.
//

import SwiftUI
import Kingfisher

struct FollowPackUsers: View {
    let state: DamusState
    var publicKeys: [Pubkey]
    
    var body: some View {
        HStack(alignment: .center) {

            if !publicKeys.isEmpty {
                CondensedProfilePicturesView(state: state, pubkeys: publicKeys, maxPictures: 5)
            }

            let followPackUserCount = publicKeys.count
            let nounString = pluralizedString(key: "follow_pack_user_count", count: followPackUserCount)
            let nounText = Text(verbatim: nounString).font(.subheadline).foregroundColor(.gray)
            Text("\(Text(verbatim: followPackUserCount.formatted()).font(.subheadline.weight(.medium))) \(nounText)", comment: "Sentence composed of 2 variables to describe how many people are in the follow pack. In source English, the first variable is the number of users, and the second variable is 'user' or 'users'.")
        }
    }
}

struct FollowPackBannerImage: View {
    let state: DamusState
    let options: EventViewOptions
    var image: URL? = nil
    var preview: Bool
    @State var blur_imgs: Bool
    
    func Placeholder(url: URL, preview: Bool) -> some View {
        Group {
            if let meta = state.events.lookup_img_metadata(url: url),
               case .processed(let blurhash) = meta.state {
                Image(uiImage: blurhash)
                    .resizable()
                    .frame(maxWidth: preview ? 350 : UIScreen.main.bounds.width, minHeight: preview ? 180 : 200, maxHeight: preview ? 180 : 200)
            } else {
                DamusColors.adaptableWhite
            }
        }
    }
    
    func titleImage(url: URL, preview: Bool) -> some View {
        KFAnimatedImage(url)
            .callbackQueue(.dispatch(.global(qos:.background)))
            .backgroundDecode(true)
            .imageContext(.note, disable_animation: state.settings.disable_animation)
            .image_fade(duration: 0.25)
            .cancelOnDisappear(true)
            .configure { view in
                view.framePreloadCount = 3
            }
            .background {
                Placeholder(url: url, preview: preview)
            }
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: preview ? 350 : UIScreen.main.bounds.width, minHeight: preview ? 180 : 200, maxHeight: preview ? 180 : 200)
            .kfClickable()
            .cornerRadius(1)
    }
    
    var body: some View {
        if let url = image {
            if (self.options.contains(.no_media)) {
                EmptyView()
            } else if !blur_imgs {
                titleImage(url: url, preview: preview)
            } else {
                ZStack {
                    titleImage(url: url, preview: preview)
                    BlurOverlayView(blur_images: $blur_imgs, artifacts: nil, size: nil, damus_state: nil, parentView: .longFormView)
                        .frame(maxWidth: preview ? 350 : UIScreen.main.bounds.width, minHeight: preview ? 180 : 200, maxHeight: preview ? 180 : 200)
                }
            }
        } else {
            Text(NSLocalizedString("No cover image", comment: "Text letting user know there is no cover image."))
                .foregroundColor(.gray)
                .frame(width: 350, height: 180)
            Divider()
        }
    }
    
}

struct FollowPackPreviewBody: View {
    let state: DamusState
    let event: FollowPackEvent
    let options: EventViewOptions
    let header: Bool
    @State var blur_imgs: Bool
    
    @ObservedObject var artifacts: NoteArtifactsModel

    init(state: DamusState, ev: FollowPackEvent, options: EventViewOptions, header: Bool, blur_imgs: Bool) {
        self.state = state
        self.event = ev
        self.options = options
        self.header = header
        self.blur_imgs = blur_imgs

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.event.id).artifacts_model)
    }

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions, header: Bool, blur_imgs: Bool) {
        self.state = state
        self.event = FollowPackEvent.parse(from: ev)
        self.options = options
        self.header = header
        self.blur_imgs = blur_imgs

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
    }

    var body: some View {
        Group {
            if options.contains(.wide) {
                Main.padding(.horizontal)
            } else {
                Main
            }
        }
    }

    var Main: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            if state.settings.media_previews {
                FollowPackBannerImage(state: state, options: options, image: event.image, preview: true, blur_imgs: blur_imgs)
            }
            
            Text(event.title ?? NSLocalizedString("Untitled", comment: "Title of follow list event if it is untitled."))
                .font(header ? .title : .headline)
                .padding(.horizontal, 10)
                .padding(.top, 5)
            
            if let description = event.description {
                Text(description)
                    .font(header ? .body : .caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 10)
            } else {
                Text("")
                    .font(header ? .body : .caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 10)
            }
            
            HStack(alignment: .center) {
                ProfilePicView(pubkey: event.event.pubkey, size: 25, highlight: .none, profiles: state.profiles, disable_animation: state.settings.disable_animation, show_zappability: true)
                    .onTapGesture {
                        state.nav.push(route: Route.ProfileByKey(pubkey: event.event.pubkey))
                    }
                let profile_txn = state.profiles.lookup(id: event.event.pubkey)
                let profile = profile_txn?.unsafeUnownedValue
                let displayName = Profile.displayName(profile: profile, pubkey: event.event.pubkey)
                switch displayName {
                case .one(let one):
                    Text(one)
                        .font(.subheadline).foregroundColor(.gray)
                    
                case .both(username: let username, displayName: let displayName):
                        HStack(spacing: 6) {
                            Text(verbatim: displayName)
                                .font(.subheadline).foregroundColor(.gray)
                            
                            Text(verbatim: "@\(username)")
                                .font(.subheadline).foregroundColor(.gray)
                        }
                }
            }
            .padding(.horizontal, 10)
            
            FollowPackUsers(state: state, publicKeys: event.publicKeys)
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
        }
        .frame(width: 350, height: state.settings.media_previews ? 330 : 150, alignment: .leading)
        .background(DamusColors.neutral3)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DamusColors.neutral1, lineWidth: 1)
        )
        .padding(.top, 10)
    }
}

struct FollowPackPreview: View {
    let state: DamusState
    let event: FollowPackEvent
    let options: EventViewOptions
    @State var blur_imgs: Bool

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions, blur_imgs: Bool) {
        self.state = state
        self.event = FollowPackEvent.parse(from: ev)
        self.options = options.union(.no_mentions)
        self.blur_imgs = blur_imgs
    }

    var body: some View {
        FollowPackPreviewBody(state: state, ev: event, options: options, header: false, blur_imgs: blur_imgs)
    }
}

let test_follow_list_event = FollowPackEvent.parse(from: NostrEvent(
    content: "",
    keypair: test_keypair,
    kind: NostrKind.longform.rawValue,
    tags: [
        ["title", "DAMUSES"],
        ["description", "Damus Team"],
        ["published_at", "1685638715"],
        ["p", "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"],
        ["p", "8b2be0a0ad34805d76679272c28a77dbede9adcbfdca48c681ec8b624a1208a6"],
        ["p", "17538dc2a62769d09443f18c37cbe358fab5bbf981173542aa7c5ff171ed77c4"],
        ["p", "520830c334a3f79f88cac934580d26f91a7832c6b21fb9625690ea2ed81b5626"],
        ["p", "2779f3d9f42c7dee17f0e6bcdcf89a8f9d592d19e3b1bbd27ef1cffd1a7f98d1"],
        ["p", "bd1e19980e2c91e6dc657e92c25762ca882eb9272d2579e221f037f93788de91"],
        ["p", "e7424ad457e512fdf4764a56bf6d428a06a13a1006af1fb8e0fe32f6d03265c7"],
        ["p", "b88c7f007bbf3bc2fcaeff9e513f186bab33782c0baa6a6cc12add78b9110ba3"],
        ["p", "4a0510f26880d40e432f4865cb5714d9d3c200ca6ebb16b418ae6c555f574967"],
        ["image", "https://damus.io/img/logo.png"],
    ])!
)


struct FollowPackPreview_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            FollowPackPreview(state: test_damus_state, ev: test_follow_list_event.event, options: [], blur_imgs: false)
        }
        .frame(height: 400)
    }
}
