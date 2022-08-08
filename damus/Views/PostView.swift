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

struct PostView: View {
    @State var post: String = "Type your post here..."
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
        let new_post = NostrPost(content: self.post, references: references)
        NotificationCenter.default.post(name: .post, object: NostrPostResult.post(new_post))
        dismiss()
    }
    
    var is_post_empty: Bool {
        return post.allSatisfy { $0.isWhitespace }
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
                .foregroundColor(self.post == "Type your post here..." ? .gray : .primary)
                .focused($focus)
                .onTapGesture {
                    if self.post.contains("Type your post here..."){
                        self.post = self.post.replacingOccurrences(of: "Type your post here...", with: "")
                    }
                }
                .onChange(of: post) { value in
                    if self.post.contains("Type your post here..."){
                        self.post = self.post.replacingOccurrences(of: "Type your post here...", with: "")
                    }
                }
    
        }
        .onAppear() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.focus = true
            }
        }
        .padding()
    }
}

