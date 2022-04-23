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

struct NostrPost {
    let content: String
    let references: [ReferencedId]
    
    public func to_event(privkey: String, pubkey: String) -> NostrEvent {
        let new_ev = NostrEvent(content: content, pubkey: pubkey)
        for id in references {
            var tag = [id.key, id.ref_id]
            if let relay_id = id.relay_id {
                tag.append(relay_id)
            }
            new_ev.tags.append(tag)
            // filter our pubkeys
            new_ev.tags = new_ev.tags.filter {
                if $0[0] == "p" {
                    return $0[1] != pubkey
                } else {
                    return true
                }
            }
        }
        new_ev.calculate_id()
        new_ev.sign(privkey: privkey)
        return new_ev
    }
}


struct PostView: View {
    @State var post: String = ""
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
        //dismiss()
    }

    var body: some View {
        VStack {
            HStack {
                Button("Cancel") {
                    self.cancel()
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

