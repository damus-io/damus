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
            Circle()
                .fill(Color(red: 0xF8/255.0, green: 0xE7/255.0, blue: 0xF8/255.0))
                .frame(width: 54, height: 54)

            switch described {
            case .hashtag:
                Text(verbatim: "#")
                    .font(.largeTitle.bold())
                    .foregroundStyle(PinkGradient)
                    .mask(Text(verbatim: "#")
                        .font(.largeTitle.bold()))

            case .unknown:
                Image(systemName: "magnifyingglass")
                    .font(.title.bold())
                    .foregroundStyle(PinkGradient)
            }
        }
    }

    var SearchText: Text {
        Text(described.description)
    }

    func unfollow(_ hashtag: String) {
        is_following = false
        handle_unfollow(state: state, unfollow: .t(hashtag))
    }

    func follow(_ hashtag: String) {
        is_following = true
        handle_follow(state: state, follow: .t(hashtag))
    }

    func FollowButton(_ ht: String) -> some View {
        return Button(action: { follow(ht) }) {
            Text("Follow hashtag", comment: "Button to follow a given hashtag.")
                .font(.footnote.bold())
        }
        .buttonStyle(GradientButtonStyle(padding: 10))
    }

    func UnfollowButton(_ ht: String) -> some View {
        return Button(action: { unfollow(ht) }) {
            Text("Unfollow hashtag", comment: "Button to unfollow a given hashtag.")
                .font(.footnote.bold())
        }
        .buttonStyle(GradientButtonStyle(padding: 10))
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
                        UnfollowButton(ht)
                    } else {
                        FollowButton(ht)
                    }
                }
            }
        }
        .onReceive(handle_notify(.followed)) { notif in
            let ref = notif.object as! ReferencedId
            guard hashtag_matches_search(desc: self.described, ref: ref) else { return }
            self.is_following = true
        }
        .onReceive(handle_notify(.unfollowed)) { notif in
            let ref = notif.object as! ReferencedId
            guard hashtag_matches_search(desc: self.described, ref: ref) else { return }
            self.is_following = false
        }
    }
}

func hashtag_matches_search(desc: DescribedSearch, ref: ReferencedId) -> Bool {
    guard let ht = desc.is_hashtag, ref.key == "t" && ref.ref_id == ht
    else { return false }
    return true
}

func is_following_hashtag(contacts: NostrEvent?, hashtag: String) -> Bool {
    guard let contacts else { return false }
    return is_already_following(contacts: contacts, follow: .t(hashtag))
}


struct SearchHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading) {
            SearchHeaderView(state: test_damus_state(), described: .hashtag("damus"))

            SearchHeaderView(state: test_damus_state(), described: .unknown)
        }
    }
}
