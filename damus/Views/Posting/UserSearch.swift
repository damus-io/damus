//
//  UserAutocompletion.swift
//  damus
//
//  Created by William Casarin on 2023-01-28.
//

import SwiftUI

struct SearchedUser: Identifiable {
    let petname: String?
    let profile: Profile?
    let pubkey: String
    
    var id: String {
        return pubkey
    }
}

struct UserSearch: View {
    let damus_state: DamusState
    let search: String

    @Binding var post: NSMutableAttributedString
    
    var users: [SearchedUser] {
        guard let contacts = damus_state.contacts.event else {
            return search_profiles(profiles: damus_state.profiles, search: search)
        }
        
        return search_users_for_autocomplete(profiles: damus_state.profiles, tags: contacts.tags, search: search)
    }
    
    func on_user_tapped(user: SearchedUser) {
        guard let pk = bech32_pubkey(user.pubkey) else {
            return
        }

        // Remove all characters after the last '@'
        removeCharactersAfterLastAtSymbol()

        // Create and append the user tag
        let tagAttributedString = createUserTag(for: user, with: pk)
        appendUserTag(tagAttributedString)
    }
    
    private func removeCharactersAfterLastAtSymbol() {
        while post.string.last != "@" {
            post.deleteCharacters(in: NSRange(location: post.length - 1, length: 1))
        }
        post.deleteCharacters(in: NSRange(location: post.length - 1, length: 1))
    }

    private func createUserTag(for user: SearchedUser, with pk: String) -> NSMutableAttributedString {
        let name = Profile.displayName(profile: user.profile, pubkey: pk).username
        let tagString = "@\(name)\u{200B} "

        let tagAttributedString = NSMutableAttributedString(string: tagString,
                                   attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18.0),
                                                NSAttributedString.Key.link: "@\(pk)"])
        tagAttributedString.removeAttribute(.link, range: NSRange(location: tagAttributedString.length - 2, length: 2))
        tagAttributedString.addAttributes([NSAttributedString.Key.foregroundColor: UIColor.label], range: NSRange(location: tagAttributedString.length - 2, length: 2))
        
        return tagAttributedString
    }

    private func appendUserTag(_ tagAttributedString: NSMutableAttributedString) {
        let mutableString = NSMutableAttributedString()
        mutableString.append(post)
        mutableString.append(tagAttributedString)
        post = mutableString
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView {
                LazyVStack {
                    if users.count == 0 {
                        EmptyUserSearchView()
                    } else {
                        ForEach(users) { user in
                            UserView(damus_state: damus_state, pubkey: user.pubkey)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    on_user_tapped(user: user)
                                }
                        }
                    }
                }
                .padding()
            }
        }
    }
}

struct UserSearch_Previews: PreviewProvider {
    static let search: String = "jb55"
    @State static var post: NSMutableAttributedString = NSMutableAttributedString(string: "some @jb55")
    
    static var previews: some View {
        UserSearch(damus_state: test_damus_state(), search: search, post: $post)
    }
}


func search_users_for_autocomplete(profiles: Profiles, tags: [[String]], search _search: String) -> [SearchedUser] {
    var seen_user = Set<String>()
    let search = _search.lowercased()
    
    var matches = tags.reduce(into: Array<SearchedUser>()) { arr, tag in
        guard tag.count >= 2 && tag[0] == "p" else {
            return
        }
        
        let pubkey = tag[1]
        guard !seen_user.contains(pubkey) else {
            return
        }
        seen_user.insert(pubkey)
        
        var petname: String? = nil
        if tag.count >= 4 {
            petname = tag[3]
        }
        
        let profile = profiles.lookup(id: pubkey)
        
        guard ((petname?.lowercased().hasPrefix(search) ?? false) ||
            (profile?.name?.lowercased().hasPrefix(search) ?? false) ||
            (profile?.display_name?.lowercased().hasPrefix(search) ?? false)) else {
            return
        }
        
        let searched_user = SearchedUser(petname: petname, profile: profile, pubkey: pubkey)
        arr.append(searched_user)
    }
    
    // search profile cache as well
    for tup in profiles.profiles.enumerated() {
        let pk = tup.element.key
        let prof = tup.element.value.profile
        
        guard !seen_user.contains(pk) else {
            continue
        }
        
        if let match = profile_search_matches(profiles: profiles, profile: prof, pubkey: pk, search: search) {
            matches.append(match)
        }
    }
    
    return matches
}
