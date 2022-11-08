//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-04-03.
//

import SwiftUI

enum NostrPostResult {
    case post(NostrPost)
    case cancel
}

let POST_PLACEHOLDER = "Type your post here..."

struct PostView: View {
    @State var post: String = POST_PLACEHOLDER
    @State var new: Bool = true

    let replying_to: NostrEvent?
    @FocusState var focus: Bool
    let references: [ReferencedId]

    @Environment(\.presentationMode) var presentationMode

    enum FocusField: Hashable {
      case post
    }

    func cancel() {
        NotificationCenter.default.post(name: .post, object: NostrPostResult.cancel)
        dismiss()
    }

    func dismiss() {
        self.presentationMode.wrappedValue.dismiss()
    }

    func send_post() {
        var kind: NostrKind = .text
        if replying_to?.known_kind == .chat {
            kind = .chat
        }
        let new_post = NostrPost(content: self.post, references: references, kind: kind)

        NotificationCenter.default.post(name: .post, object: NostrPostResult.post(new_post))
        dismiss()
    }

    var is_post_empty: Bool {
        return post == POST_PLACEHOLDER || post.allSatisfy { $0.isWhitespace }
    }

    var body: some View {
        VStack {
            HStack {
                Button("Cancel") {
                    self.cancel()
                }
                .foregroundColor(.primary)

                Spacer()

                if !is_post_empty {
                    Button("Post") {
                        self.send_post()
                    }
                }
            }
            .padding([.top, .bottom], 4)


            TextEditor(text: $post)
                .foregroundColor(self.post == POST_PLACEHOLDER ? .gray : .primary)
                .focused($focus)
                .textInputAutocapitalization(.sentences)
                .onTapGesture {
                    handle_post_placeholder()
                }
                .onChange(of: post) { value in
                    handle_post_placeholder()
                }

        }
        .onAppear() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.focus = true
            }
        }
        .padding()
    }

    func handle_post_placeholder()  {
        guard new else {
            return
        }

        new = false
        post = post.replacingOccurrences(of: POST_PLACEHOLDER, with: "")
    }
}

