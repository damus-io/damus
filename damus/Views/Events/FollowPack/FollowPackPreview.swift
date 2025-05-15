//
//  FollowPackPreview.swift
//  damus
//
//  Created by eric on 4/30/25.
//

import SwiftUI
import Kingfisher

struct FollowPackPreviewBody: View {
    let state: DamusState
    let event: FollowPackEvent
    let options: EventViewOptions
    let header: Bool
    @State var blur_images: Bool = true
    
    @ObservedObject var artifacts: NoteArtifactsModel

    init(state: DamusState, ev: FollowPackEvent, options: EventViewOptions, header: Bool) {
        self.state = state
        self.event = ev
        self.options = options
        self.header = header

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.event.id).artifacts_model)
    }

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions, header: Bool) {
        self.state = state
        self.event = FollowPackEvent.parse(from: ev)
        self.options = options
        self.header = header

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
    }
    
    func Placeholder(url: URL) -> some View {
        Group {
            if let meta = state.events.lookup_img_metadata(url: url),
               case .processed(let blurhash) = meta.state {
                Image(uiImage: blurhash)
                    .resizable()
                    .frame(width: 350, height: 150)
            } else {
                DamusColors.adaptableWhite
            }
        }
    }
    
    func titleImage(url: URL) -> some View {
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
                Placeholder(url: url)
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 350, height: 150)
            .kfClickable()
            .cornerRadius(1)
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
            if let url = event.image {
                if (self.options.contains(.no_media)) {
                    EmptyView()
                } else if !blur_images || (!blur_images && !state.settings.media_previews) {
                    titleImage(url: url)
                } else if blur_images || (blur_images && !state.settings.media_previews) {
                    ZStack {
                        titleImage(url: url)
                        BlurOverlayView(blur_images: $blur_images, artifacts: nil, size: nil, damus_state: nil, parentView: .longFormView)
                    }
                }
            } else {
                Text("No cover image")
                    .foregroundColor(.gray)
                    .frame(width: 350, height: 150)
                Divider()
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
                EmptyView()
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
            
            HStack(alignment: .center) {
                if !event.publicKeys.isEmpty {
                    CondensedProfilePicturesView(state: state, pubkeys: event.publicKeys, maxPictures: 5)
                    
                    Text("· \(event.publicKeys.count) users")
                        .font(.subheadline).foregroundColor(.gray)
                        .padding(.top, 4)
                } else {
                    Text("0 users")
                        .font(.subheadline).foregroundColor(.gray)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 20)
        }
        .frame(width: 350, height: 300, alignment: .leading)
        .background(DamusColors.neutral3)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DamusColors.neutral1, lineWidth: 1)
        )
        .padding(.top, 10)
        .onAppear {
            blur_images = should_blur_images(settings: state.settings, contacts: state.contacts, ev: event.event, our_pubkey: state.pubkey)
        }
    }
}

struct FollowPackPreview: View {
    let state: DamusState
    let event: FollowPackEvent
    let options: EventViewOptions

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = FollowPackEvent.parse(from: ev)
        self.options = options.union(.no_mentions)
    }

    var body: some View {
        FollowPackPreviewBody(state: state, ev: event, options: options, header: false)
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
        ["p", "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"],
        ["p", "npub13v47pg9dxjq96an8jfev9znhm0k7ntwtlh9y335paj9kyjsjpznqzzl3l8"],
        ["p", "npub1zafcms4xya5ap9zr7xxr0jlrtrattwlesytn2s42030lzu0dwlzqpd26k5"],
        ["p", "npub12gyrpse550melzx2ey69srfxlyd8svkxkg0mjcjkjr4zakqm2cnqwa3jj5"],
        ["p", "npub1yaul8k059377u9lsu67de7y637w4jtgeuwcmh5n7788l6xnlnrgs3tvjmf"],
        ["p", "npub1h50pnxqw9jg7dhr906fvy4mze2yzawf895jhnc3p7qmljdugm6gsrurqev"],
        ["p", "npub1uapy44zhu5f0markfftt7m2z3gr2zwssq6h3lw8qlce0d5pjvhrs3q9pmv"],
        ["p", "npub1hzx87qrmhuau9l9wl709z0ccdw4nx7pvpw4x5mxp9twh3wg3pw3svjjhe7"],
        ["p", "npub1fgz3pungsr2quse0fpjuk4c5m8fuyqx2d6a3ddqc4ek92h6hf9ns0mjeck"],
        ["image", "https://damus.io/img/logo.png"],
    ])!
)


struct FollowPackPreview_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            FollowPackPreview(state: test_damus_state, ev: test_follow_list_event.event, options: [])
        }
        .frame(height: 400)
    }
}
