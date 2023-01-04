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

let POST_PLACEHOLDER = NSLocalizedString("Type your post here...", comment: "Text box prompt to ask user to type their post.")

struct PostView: View {
    @State var post: String = ""
    @State var displayPolls: Bool = true
    @State var polls: [String] = ["", ""]

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
        let content = self.post.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let new_post = NostrPost(content: content, references: references, kind: kind)

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
            
             
            if displayPolls {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(0 ..< polls.count, id: \.self) { index in
                        HStack {
                            TextField("Choice \(index + 1)", text: self.$polls[index])
                                .padding(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                                )
                                .cornerRadius(10)
                            Button(action: {
                                self.polls.remove(at: index)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.red.opacity(self.polls.count <= 2 ? 0.5 : 1))
                            }
                            .disabled(self.polls.count <= 2)
                        }
                    }
                    
                    if self.polls.count <= 3 {
                        Button(action: {
                            self.polls.append("")
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                                .padding(.trailing, 10)
                            Text("Add choice")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                )
                .cornerRadius(10)
            }
            
            
            ZStack(alignment: .topLeading) {
                TextEditor(text: $post)
                    .focused($focus)
                    .textInputAutocapitalization(.sentences)
                if post.isEmpty {
                    Text(POST_PLACEHOLDER)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .foregroundColor(Color(uiColor: .placeholderText))
                        .allowsHitTesting(false)
                }
            }
            
            VStack {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Button {
                        withAnimation {
                            displayPolls.toggle()
                        }
                    } label: {
                        Label("&nbsp;", systemImage: "filemenu.and.selection")
                            .font(.title2)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .padding([.top, .bottom], 5)
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

struct PostView_Previews: PreviewProvider {
    static var previews: some View {
        PostView(replying_to: nil, references: [])
    }
}
