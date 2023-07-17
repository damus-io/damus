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

        appendUserTag(withTag: user_tag)
    }

    private func appendUserTag(withTag tag: NSMutableAttributedString) {
        guard let wordRange = focusWordAttributes.1 else { return }

        let appended = append_user_tag(tag: tag, post: post, word_range: wordRange)
        self.post = appended.post

        // adjust cursor position appropriately: ('diff' used in TextViewWrapper / updateUIView after below update of 'post')
        tagModel.diff = appended.tag.length - wordRange.length

        focusWordAttributes = (nil, nil)
        newCursorIndex = wordRange.location + appended.tag.string.count
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

/// Pad an attributed string: `@jb55` -> ` @jb55 `
func pad_attr_string(tag: NSAttributedString, before: Bool = true) -> NSAttributedString {
    let new_tag = NSMutableAttributedString(string: "")
    if before {
        new_tag.append(.init(string: " "))
    }

    new_tag.append(tag)
    new_tag.append(.init(string: " "))
    return new_tag
}

/// Checks if whitespace precedes a tag. Useful to add spacing if we don't have it.
func should_prepad_tag(tag: NSAttributedString, post: NSMutableAttributedString, word_range: NSRange) -> Bool {
    if word_range.location == 0 { // If the range starts at the very beginning of the post, there's nothing preceding it.
        return false
    }

    // Range for the character preceding the tag
    let precedingCharacterRange = NSRange(location: word_range.location - 1, length: 1)

    // Get the preceding character
    let precedingCharacter = post.attributedSubstring(from: precedingCharacterRange)

    guard let char = precedingCharacter.string.first else {
        return false
    }

    if char.isNewline {
        return false
    }

    // Check if the preceding character is a whitespace character
    return !char.isWhitespace
}

struct AppendedTag {
    let post: NSMutableAttributedString
    let tag: NSAttributedString
}

/// Appends a user tag (eg: @jb55) to a post. This handles adding additional padding as well.
func append_user_tag(tag: NSAttributedString, post: NSMutableAttributedString, word_range: NSRange) -> AppendedTag {
    let new_post = NSMutableAttributedString(attributedString: post)

    // If we have a non-empty post and the last character is not whitespace, append a space
    // This prevents issues such as users typing cc@will and have it expand to ccnostr:bech32...
    let should_prepad = should_prepad_tag(tag: tag, post: post, word_range: word_range)
    let tag = pad_attr_string(tag: tag, before: should_prepad)

    new_post.replaceCharacters(in: word_range, with: tag)

    return AppendedTag(post: new_post, tag: tag)
}

/// Generate a mention attributed string, including the internal damus:nostr: link
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

