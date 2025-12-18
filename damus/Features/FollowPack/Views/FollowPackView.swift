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
    @StateObject var model: FollowPackModel
    @State var blur_imgs: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var artifacts: NoteArtifactsModel

    init(state: DamusState, ev: FollowPackEvent, model: FollowPackModel, blur_imgs: Bool) {
        self.state = state
        self.event = ev
        self._model = StateObject(wrappedValue: model)
        self.blur_imgs = blur_imgs

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.event.id).artifacts_model)
    }

    init(state: DamusState, ev: NostrEvent, model: FollowPackModel, blur_imgs: Bool) {
        self.state = state
        self.event = FollowPackEvent.parse(from: ev)
        self._model = StateObject(wrappedValue: model)
        self.blur_imgs = blur_imgs

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
    }
    
    func content_filter(_ pubkeys: [Pubkey]) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: self.state)
        filters.append({ pubkeys.contains($0.pubkey) })
        return ContentFilters(filters: filters).filter
    }
    
    enum FollowPackTabSelection: Int {
        case people = 0
        case posts = 1
    }
    
    @State var tab_selection: FollowPackTabSelection = .people
    
    var body: some View {
        ZStack {
            ScrollView {
                FollowPackHeader
                
                FollowPackTabs
            }
        }
        .onAppear {
            if model.events.events.isEmpty {
                model.subscribe(follow_pack_users: event.publicKeys)
            }
        }
        .onDisappear {
            model.unsubscribe()
        }
    }
    
    var tabs: [(String, FollowPackTabSelection)] {
        let tabs = [
            (NSLocalizedString("People", comment: "Label for filter for seeing the people in this follow pack."), FollowPackTabSelection.people),
            (NSLocalizedString("Posts", comment: "Label for filter for seeing the posts from the people in this follow pack."), FollowPackTabSelection.posts)
            ]
        return tabs
    }
    
    var FollowPackTabs: some View {

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                CustomPicker(tabs: tabs, selection: $tab_selection)
                Divider()
                    .frame(height: 1)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            
            if tab_selection == FollowPackTabSelection.people {
                LazyVStack(alignment: .leading) {
                    ForEach(event.publicKeys.reversed(), id: \.self) { pk in
                        FollowUserView(target: .pubkey(pk), damus_state: state)
                    }
                }
                .padding()
                .padding(.bottom, 50)
                .tag(FollowPackTabSelection.people)
                .id(FollowPackTabSelection.people)
            }
            
            if tab_selection == FollowPackTabSelection.posts {
                InnerTimelineView(events: model.events, damus: state, filter: content_filter(event.publicKeys))
            }
        }
        .onAppear() {
            model.subscribe(follow_pack_users: event.publicKeys)
        }
        .onDisappear {
            model.unsubscribe()
        }
    }

    var FollowPackHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            if state.settings.media_previews {
                FollowPackBannerImage(state: state, options: EventViewOptions(), image: event.image, preview: false, blur_imgs: blur_imgs)
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
                ProfilePicView(pubkey: event.event.pubkey, size: 25, highlight: .none, profiles: state.profiles, disable_animation: state.settings.disable_animation, show_zappability: true, damusState: state)
                    .onTapGesture {
                        state.nav.push(route: Route.ProfileByKey(pubkey: event.event.pubkey))
                    }
                let profile = try? state.profiles.lookup(id: event.event.pubkey)
                let displayName = Profile.displayName(profile: profile, pubkey: event.event.pubkey)
                switch displayName {
                case .one(let one):
                    Text("Created by \(one)", comment: "Lets the user know who created this follow pack.")
                        .font(.subheadline).foregroundColor(.gray)
                    
                case .both(username: let username, displayName: let displayName):
                        HStack(spacing: 6) {
                            Text("Created by \(displayName)", comment: "Lets the user know who created this follow pack.")
                                .font(.subheadline).foregroundColor(.gray)
                            
                            Text(verbatim: "@\(username)")
                                .font(.subheadline).foregroundColor(.gray)
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 20)
            
            HStack(alignment: .center) {
                FollowPackUsers(state: state, publicKeys: event.publicKeys)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 20)
        }
    }
}


struct FollowPackView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            FollowPackView(state: test_damus_state, ev: test_follow_list_event, model: FollowPackModel(damus_state: test_damus_state), blur_imgs: false)
        }
        .frame(height: 400)
    }
}
