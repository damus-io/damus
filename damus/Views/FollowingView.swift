//
//  FollowingView.swift
//  damus
//
//  Created by William Casarin on 2022-05-16.
//

import SwiftUI

struct FollowUserView: View {
    let target: FollowTarget
    let damus_state: DamusState

    var body: some View {
        HStack {
            UserViewRow(damus_state: damus_state, pubkey: target.pubkey)
                .onTapGesture {
                    damus_state.nav.push(route: Route.ProfileByKey(pubkey: target.pubkey))
                }
            
            FollowButtonView(target: target, follows_you: false, follow_state: damus_state.contacts.follow_state(target.pubkey))
        }
        Spacer()
    }
}

struct FollowHashtagView: View {
    let hashtag: Hashtag
    let damus_state: DamusState
    @State var is_following: Bool
    
    init(hashtag: Hashtag, damus_state: DamusState) {
        self.hashtag = hashtag
        self.damus_state = damus_state
        self.is_following = damus_state.contacts.follows(hashtag: hashtag)
    }

    var body: some View {
        HStack {
            HStack {
                SingleCharacterAvatar(character: "#")
                
                Text(verbatim: "#\(hashtag.hashtag)")
                    .bold()
            }
            .onTapGesture {
                let search = SearchModel(state: damus_state, search: NostrFilter.init(hashtag: [hashtag.hashtag]))
                damus_state.nav.push(route: Route.Search(search: search))
            }
            
            Spacer()
            if is_following {
                HashtagUnfollowButton(damus_state: damus_state, hashtag: hashtag.hashtag, is_following: $is_following)
            }
            else {
                HashtagFollowButton(damus_state: damus_state, hashtag: hashtag.hashtag, is_following: $is_following)
            }
        }
        .onReceive(handle_notify(.followed)) { follow in
            guard case .hashtag(let ht) = follow, ht == hashtag.hashtag else {
                return
            }
            self.is_following = true
        }
        .onReceive(handle_notify(.unfollowed)) { follow in
            guard case .hashtag(let ht) = follow, ht == hashtag.hashtag else {
                return
            }
            self.is_following = false
        }
    }
}

struct FollowersYouKnowView: View {
    let damus_state: DamusState
    let friended_followers: [Pubkey]
    @ObservedObject var followers: FollowersModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(friended_followers, id: \.self) { pk in
                    FollowUserView(target: .pubkey(pk), damus_state: damus_state)
                }
            }
            .padding(.horizontal)
        }
        .navigationBarTitle(NSLocalizedString("Followers You Know", comment: "Navigation bar title for view that shows who is following a user."))
    }
}

struct FollowersView: View {
    let damus_state: DamusState
    @ObservedObject var followers: FollowersModel
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(followers.contacts ?? [], id: \.self) { pk in
                    FollowUserView(target: .pubkey(pk), damus_state: damus_state)
                }
            }
            .padding(.horizontal)
        }
        .navigationBarTitle(NSLocalizedString("Followers", comment: "Navigation bar title for view that shows who is following a user."))
        .onAppear {
            followers.subscribe()
        }
        .onDisappear {
            followers.unsubscribe()
        }
    }
}

enum FollowingViewTabSelection: Int {
    case people = 0
    case hashtags = 1
}

struct FollowingView: View {
    let damus_state: DamusState
    
    let following: FollowingModel
    @State var tab_selection: FollowingViewTabSelection = .people
    @Environment(\.colorScheme) var colorScheme

    
    var body: some View {
        TabView(selection: $tab_selection) {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(following.contacts.reversed(), id: \.self) { pk in
                        FollowUserView(target: .pubkey(pk), damus_state: damus_state)
                    }
                }
                .padding()
            }
            .tag(FollowingViewTabSelection.people)
            .id(FollowingViewTabSelection.people)
            
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(following.hashtags, id: \.self) { ht in
                        FollowHashtagView(hashtag: ht, damus_state: damus_state)
                    }
                }
                .padding()
            }
            .tag(FollowingViewTabSelection.hashtags)
            .id(FollowingViewTabSelection.hashtags)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
            following.subscribe()
        }
        .onDisappear {
            following.unsubscribe()
        }
        .navigationBarTitle(NSLocalizedString("Following", comment: "Navigation bar title for view that shows who a user is following."))
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CustomPicker(selection: $tab_selection, content: {
                    Text("People", comment: "Label for filter for seeing only people follows.").tag(FollowingViewTabSelection.people)
                    Text("Hashtags", comment: "Label for filter for seeing only hashtag follows.").tag(FollowingViewTabSelection.hashtags)
                })
                Divider()
                    .frame(height: 1)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }
}


struct FollowingView_Previews: PreviewProvider {
    static var previews: some View {
        FollowingView(damus_state: test_damus_state, following: test_following_model)
    }
}

