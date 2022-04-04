//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-04-03.
//

import SwiftUI

extension Notification.Name {
    static var post: Notification.Name {
        return Notification.Name("send post")
    }
}

struct NostrPost {
    let content: String
}


struct PostView: View {
    @State var post: String = ""
    @FocusState var focus: Bool

    @Environment(\.presentationMode) var presmode

    enum FocusField: Hashable {
      case post
    }

    func dismiss() {
        presmode.wrappedValue.dismiss()
    }

    func send_post() {
        let new_post = NostrPost(content: self.post)
        NotificationCenter.default.post(name: .post, object: new_post)
        dismiss()
    }

    var body: some View {
        VStack {
            HStack {
                Button("Cancel") {
                    self.dismiss()
                }
                .foregroundColor(.primary)

                Spacer()

                Button("Post") {
                    self.send_post()
                }
            }
            .padding([.top, .bottom], 4)

            HStack(alignment: .top) {
                ZStack(alignment: .leading) {
                    TextEditor(text: $post)
                        .focused($focus)

                    if self.post == "" {
                        VStack {
                            Text("What's happening?")
                                .foregroundColor(.gray)
                                .padding(6)
                            Spacer()
                        }
                    }
                }


                Spacer()
            }

            Spacer()
        }
        .onAppear() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.focus = true
            }
        }
        .padding()
    }
}

