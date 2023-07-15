//
//  UserAutocompletion.swift
//  damus
//
//  Created by William Casarin on 2023-01-28.
//

import SwiftUI

struct SearchedUser: Identifiable {
    let profile: Profile?
    let pubkey: String
    
    var id: String {
        return pubkey
    }
}

struct UserSearch: View {
    let damus_state: DamusState
    let search: String
    @Binding var focusWordAttributes: (String?, NSRange?)
    @Binding var newCursorIndex: Int?
    @Binding var postTextViewCanScroll: Bool

    @Binding var post: NSMutableAttributedString
    @EnvironmentObject var tagModel: TagModel
    
    var users: [SearchedUser] {
        return search_profiles(profiles: damus_state.profiles, search: search)
    }
    
    func on_user_tapped(user: SearchedUser) {
        guard let pk = bech32_pubkey(user.pubkey) else {
            return
        }

        let user_tag = user_tag_attr_string(profile: user.profile, pubkey: pk)
        user_tag.append(.init(string: " "))

        appendUserTag(withTag: user_tag)
    }

    private func appendUserTag(withTag tagAttributedString: NSMutableAttributedString) {
        guard let wordRange = focusWordAttributes.1 else {
            return
        }
        let mutableString = NSMutableAttributedString(attributedString: post)
        mutableString.replaceCharacters(in: wordRange, with: tagAttributedString)
        ///adjust cursor position appropriately: ('diff' used in TextViewWrapper / updateUIView after below update of 'post')
        tagModel.diff = tagAttributedString.length - wordRange.length
        
        post = mutableString
        focusWordAttributes = (nil, nil)
        newCursorIndex = wordRange.location + tagAttributedString.string.count
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
        .onAppear() {
            postTextViewCanScroll = false
        }
        .onDisappear() {
            postTextViewCanScroll = true
        }
    }
        
}

struct UserSearch_Previews: PreviewProvider {
    static let search: String = "jb55"
    @State static var post: NSMutableAttributedString = NSMutableAttributedString(string: "some @jb55")
    @State static var word: (String?, NSRange?) = (nil, nil)
    @State static var newCursorIndex: Int?
    @State static var postTextViewCanScroll: Bool = false
    
    static var previews: some View {
        UserSearch(damus_state: test_damus_state(), search: search, focusWordAttributes: $word, newCursorIndex: $newCursorIndex, postTextViewCanScroll: $postTextViewCanScroll, post: $post)
    }
}

func user_tag_attr_string(profile: Profile?, pubkey: String) -> NSMutableAttributedString {
    let display_name = Profile.displayName(profile: profile, pubkey: pubkey)
    let name = display_name.username.truncate(maxLength: 50)
    let tagString = "@\(name)"

    return NSMutableAttributedString(string: tagString, attributes: [
        NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18.0),
        NSAttributedString.Key.foregroundColor: UIColor.label,
        NSAttributedString.Key.link: "damus:nostr:\(pubkey)"
    ])
}

