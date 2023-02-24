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
            return []
        }
        
        return search_users(profiles: damus_state.profiles, tags: contacts.tags, search: search)
    }
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(users) { user in
                    UserView(damus_state: damus_state, pubkey: user.pubkey)
                        .onTapGesture {
                            guard let pk = bech32_pubkey(user.pubkey) else {
                                return
                            }

                            while post.string.last != "@" {
                                post.deleteCharacters(in: NSRange(location: post.length - 1, length: 1))
                            }
                            post.deleteCharacters(in: NSRange(location: post.length - 1, length: 1))


                            var tagString = ""
                            if let name = user.profile?.name {
                                tagString = "@\(name)\u{200B} "
                            }
                            let tagAttributedString = NSMutableAttributedString(string: tagString,
                                                   attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18.0),
                                                                NSAttributedString.Key.link: "@\(pk)"])
                            tagAttributedString.removeAttribute(.link, range: NSRange(location: tagAttributedString.length - 2, length: 2))
                            let mutableString = NSMutableAttributedString()
                            mutableString.append(post)
                            mutableString.append(tagAttributedString)
                            post = mutableString
                        }
                }
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


func search_users(profiles: Profiles, tags: [[String]], search _search: String) -> [SearchedUser] {
    var seen_user = Set<String>()
    let search = _search.lowercased()
    
    return tags.reduce(into: Array<SearchedUser>()) { arr, tag in
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
        
        guard ((petname?.lowercased().hasPrefix(search) ?? false) || (profile?.name?.lowercased().hasPrefix(search) ?? false)) else {
            return
        }
        
        let searched_user = SearchedUser(petname: petname, profile: profile, pubkey: pubkey)
        arr.append(searched_user)
    }
}
