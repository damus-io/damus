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
    @State var post: String = ""
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
        presentationMode.wrappedValue.dismiss()
    }

    func send_post() {
        var kind: NostrKind = .text
        if replying_to?.known_kind == .chat {
            kind = .chat
        }
        let content = post.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let new_post = NostrPost(content: content, references: references, kind: kind)

        NotificationCenter.default.post(name: .post, object: NostrPostResult.post(new_post))
        dismiss()
    }

    var body: some View {
        VStack {
            HStack {
                Button("Cancel") {
                    self.cancel()
                }
                .foregroundColor(.primary)

                Spacer()

                if !post.isEmpty {
                    Button("Post") {
                        self.send_post()
                    }
                }
            }
            .padding([.top, .bottom], 4)

            ZStack(alignment: .leading) {
                if post.isEmpty {
                    VStack {
                        Text(POST_PLACEHOLDER)
                            .padding(.top, 10)
                            .padding(.leading, 6)
                            .foregroundColor(.primary)
                            .focused($focus)
                        Spacer()
                    }
                }

                VStack {
                    TextEditor(text: $post)
                        .frame(minHeight: 150, maxHeight: 300)
                        .opacity(post.isEmpty ? 0.7 : 1)
                        .focused($focus)
                        .foregroundColor(.primary)
                        .textInputAutocapitalization(.sentences)
                    Spacer()
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.focus = true
            }
        }
        .padding()
    }
}
