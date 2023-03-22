//
//  SearchIconView.swift
//  damus
//
//  Created by William Casarin on 2023-07-12.
//

import SwiftUI

struct SearchHeaderView: View {
    let state: DamusState
    let described: DescribedSearch
    @State var is_following: Bool

    init(state: DamusState, described: DescribedSearch) {
        self.state = state
        self.described = described

        let is_following = (described.is_hashtag.map {
            ht in is_following_hashtag(contacts: state.contacts.event, hashtag: ht)
        }) ?? false

        self._is_following = State(wrappedValue: is_following)
    }

    var Icon: some View {
        ZStack {
            switch described {
                case .hashtag:
                    SingleCharacterAvatar(character: "#")
                case .unknown:
                    SystemIconAvatar(system_name: "magnifyingglass")
            }
        }
    }

    var SearchText: Text {
        Text(described.description)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            Icon

            VStack(alignment: .leading, spacing: 10.0) {
                SearchText
                    .foregroundStyle(DamusLogoGradient.gradient)
                    .font(.title.bold())

                if state.is_privkey_user, case .hashtag(let ht) = described {
                    if is_following {
                        HashtagUnfollowButton(damus_state: state, hashtag: ht, is_following: $is_following)
                    } else {
                        HashtagFollowButton(damus_state: state, hashtag: ht, is_following: $is_following)
                    }
                }
            }
        }
        .onReceive(handle_notify(.followed)) { ref in
            guard hashtag_matches_search(desc: self.described, ref: ref) else { return }
            self.is_following = true
        }
        .onReceive(handle_notify(.unfollowed)) { ref in
            guard hashtag_matches_search(desc: self.described, ref: ref) else { return }
            self.is_following = false
        }
    }
}

struct SystemIconAvatar: View {
    let system_name: String
    
    var body: some View {
        NonImageAvatar {
            Image(systemName: system_name)
                .font(.title.bold())
        }
    }
}

struct SingleCharacterAvatar: View {
    let character: String
    
    var body: some View {
        NonImageAvatar {
            Text(verbatim: character)
                .font(.largeTitle.bold())
                .mask(Text(verbatim: character)
                    .font(.largeTitle.bold()))
        }
    }
}

struct NonImageAvatar<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(DamusColors.lightBackgroundPink)
                .frame(width: 54, height: 54)
            
            content
                .foregroundStyle(PinkGradient)
        }
    }
}

struct HashtagUnfollowButton: View {
    let damus_state: DamusState
    let hashtag: String
    @Binding var is_following: Bool
    
    var body: some View {
        return Button(action: { unfollow(hashtag) }) {
            Text("Unfollow hashtag", comment: "Button to unfollow a given hashtag.")
                .font(.footnote.bold())
        }
        .buttonStyle(GradientButtonStyle(padding: 10))
    }
        
    func unfollow(_ hashtag: String) {
        is_following = false
        handle_unfollow(state: damus_state, unfollow: FollowRef.hashtag(hashtag))
    }
}

struct HashtagFollowButton: View {
    let damus_state: DamusState
    let hashtag: String
    @Binding var is_following: Bool
    
    var body: some View {
        return Button(action: { follow(hashtag) }) {
            Text("Follow hashtag", comment: "Button to follow a given hashtag.")
                .font(.footnote.bold())
        }
        .buttonStyle(GradientButtonStyle(padding: 10))
    }
    
    func follow(_ hashtag: String) {
        is_following = true
        handle_follow(state: damus_state, follow: .hashtag(hashtag))
    }
}

func hashtag_matches_search(desc: DescribedSearch, ref: FollowRef) -> Bool {
    guard case .hashtag(let follow_ht) = ref,
          case .hashtag(let search_ht) = desc,
          follow_ht == search_ht
    else {
        return false
    }

    return true
}

func is_following_hashtag(contacts: NostrEvent?, hashtag: String) -> Bool {
    guard let contacts else { return false }
    return is_already_following(contacts: contacts, follow: .hashtag(hashtag))
}


struct SearchHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading) {
            SearchHeaderView(state: test_damus_state, described: .hashtag("damus"))

            SearchHeaderView(state: test_damus_state, described: .unknown)
        }
    }
}
