//
//  FollowPackView.swift
//  damus
//
//  Created by eric on 4/30/25.
//

import SwiftUI
import Kingfisher

struct FollowPackView: View {
    let state: DamusState
    let event: FollowPackEvent
    @State var blur_images: Bool = true
    
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var artifacts: NoteArtifactsModel

    init(state: DamusState, ev: FollowPackEvent) {
        self.state = state
        self.event = ev

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.event.id).artifacts_model)
    }

    init(state: DamusState, ev: NostrEvent) {
        self.state = state
        self.event = FollowPackEvent.parse(from: ev)

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
    }
    
    func Placeholder(url: URL) -> some View {
        Group {
            if let meta = state.events.lookup_img_metadata(url: url),
               case .processed(let blurhash) = meta.state {
                Image(uiImage: blurhash)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: 200)
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
            .frame(maxHeight: 200)
            .kfClickable()
            .cornerRadius(15)
    }
    
    enum FollowPackTabSelection: Int {
        case people = 0
        case posts = 1
    }
    
    @State var tab_selection: FollowPackTabSelection = .people

    var body: some View {
        Group {
            Main
            
            PackTabs
        }
    }
    
    var PackTabs: some View {
        
        TabView(selection: $tab_selection) {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(event.publicKeys.reversed(), id: \.self) { pk in
                        FollowUserView(target: .pubkey(pk), damus_state: state)
                    }
                }
                .padding()
            }
            .padding(.bottom, 50)
            .tag(FollowPackTabSelection.people)
            .id(FollowPackTabSelection.people)
            
//            ScrollView {
//                LazyVStack(alignment: .leading) {
//                }
//                .padding()
//            }
//            .padding(.bottom, 50)
//            .tag(FollowPackTabSelection.posts)
//            .id(FollowPackTabSelection.posts)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CustomPicker(tabs: [
                    (NSLocalizedString("People", comment: "Label for filter for seeing the people in this follow pack."), FollowPackTabSelection.people),
//                    (NSLocalizedString("Posts", comment: "Label for filter for seeing the posts from people in this follow pack."), FollowPackTabSelection.posts)
                ], selection: $tab_selection)
                Divider()
                    .frame(height: 1)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }

    var Main: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = event.image {
                if !blur_images || (!blur_images && !state.settings.media_previews) {
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
                    .frame(maxHeight: 200)
                Divider()
            }
            
            Text(event.title ?? NSLocalizedString("Untitled", comment: "Title of follow list event if it is untitled."))
                .font(.title)
                .padding(.horizontal, 10)
                .padding(.top, 5)
            
            if let description = event.description {
                Text(description)
                    .font(.body)
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
                    Text("Created by \(one)")
                        .font(.subheadline).foregroundColor(.gray)
                    
                case .both(username: let username, displayName: let displayName):
                        HStack(spacing: 6) {
                            Text(verbatim: "Created by \(displayName)")
                                .font(.subheadline).foregroundColor(.gray)
                            
                            Text(verbatim: "@\(username)")
                                .font(.subheadline).foregroundColor(.gray)
                        }
                }
            }
            .padding(.horizontal, 10)
            
            HStack(alignment: .center) {
                if !event.publicKeys.isEmpty {
                    Text("Total of \(event.publicKeys.count) users")
                        .font(.subheadline).foregroundColor(.gray)
                        .padding(.top, 4)
                } else {
                    Text("0 users")
                        .font(.subheadline).foregroundColor(.gray)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 7)
                }
                
                Spacer()
                
                Button(action: {
                    for pubkey in event.publicKeys {
                        notify(.follow(.pubkey(pubkey)))
                    }
                }) {
                    Text(NSLocalizedString("Follow All", comment: "Button to follow all users in this section"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(GradientButtonStyle(padding: 9))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 20)
        }
        .onAppear {
            blur_images = should_blur_images(settings: state.settings, contacts: state.contacts, ev: event.event, our_pubkey: state.pubkey)
        }
    }
}


struct FollowPackView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            FollowPackView(state: test_damus_state, ev: test_follow_list_event)
        }
        .frame(height: 400)
    }
}
