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
                            
                            ///TODO - move below constant & method-call outside this ForEach loop (and optimize property scopes)
                            let components = post.string.components(separatedBy: .whitespacesAndNewlines)
                            let (tagLength,tagIndex,tagWordIndex) = tagProperties(from: components)
                            
                            let mutableString = NSMutableAttributedString()
                            mutableString.append(post)
                            
                            // replace tag-search word with tag attributed string
                            mutableString.deleteCharacters(in: NSRange(location: tagIndex, length: tagLength))
                            let tagAttributedString = tagAttributedString(user, pk: pk)
                            mutableString.insert(tagAttributedString, at: tagIndex)
                            
                            // if no tag at end of post, insert extra space at end
                            if mutableString.string.last != " ", tagWordIndex != components.count - 1 {
                                let endSpace = plainAttributedString(string: " ")
                                mutableString.insert(endSpace, at: mutableString.length)
                            }
                            post = mutableString
                        }
                }
            }
        }
    }
    
    private func tagProperties(from components: [String]) -> (Int,Int,Int) {
        var tagLength = 0, tagIndex = 0 // index of the start of a tag in a post
        var tagWordIndex = 0            // index of the word containing a tag
        
        for (index,word) in components.enumerated() {
            if word.first == "@" {
                tagLength = word.count
                tagWordIndex = index
                break // this logic can be updated to support tagging multiple users
            }
            tagIndex += (word.count == 0) ? (1) : (1 + word.count)
        }
        return (tagLength,tagIndex,tagWordIndex)
    }
    
    private func tagAttributedString(_ user: SearchedUser, pk: String) -> NSMutableAttributedString {
        var tagString = ""
        if let name = user.profile?.name {
            searchedNames.append("@\(name)")
            tagString = "@\(name)\u{200B} "
        }
        let tagAttributedString = NSMutableAttributedString(string: tagString,
                                                            attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18.0),
                                                                         NSAttributedString.Key.link: "@\(pk)"])
        tagAttributedString.removeAttribute(.link, range: NSRange(location: tagAttributedString.length - 2, length: 2))
        tagAttributedString.addAttributes([NSAttributedString.Key.foregroundColor: UIColor.label], range: NSRange(location: tagAttributedString.length - 2, length: 2))
        return tagAttributedString
    }
    
    private func plainAttributedString(string: String) -> NSMutableAttributedString {
        let tagAttributedString = NSMutableAttributedString(string: string,
                                                            attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18.0)])
        tagAttributedString.addAttributes([NSAttributedString.Key.foregroundColor: UIColor.label], range: NSRange(location: tagAttributedString.length - 1, length: 1))
        return tagAttributedString
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
        if !searchedNames.contains("@\(searched_user.profile?.name ?? "")") {
            arr.append(searched_user)
        }
    }
}
