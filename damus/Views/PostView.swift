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
    @State var post: NSMutableAttributedString = NSMutableAttributedString()
    @FocusState var focus: Bool
    @State var showPrivateKeyWarning: Bool = false
    @State var attach_media: Bool = false
    @State var error: String? = nil
    
    @StateObject var image_upload: ImageUploadModel = ImageUploadModel()

    let replying_to: NostrEvent?
    let references: [ReferencedId]
    let damus_state: DamusState

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

        post.enumerateAttributes(in: NSRange(location: 0, length: post.length), options: []) { attributes, range, stop in
            if let link = attributes[.link] as? String {
                post.replaceCharacters(in: range, with: link)
            }
        }

        let content = self.post.string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let new_post = NostrPost(content: content, references: references, kind: kind)

        NotificationCenter.default.post(name: .post, object: NostrPostResult.post(new_post))

        if let replying_to {
            damus_state.drafts.replies.removeValue(forKey: replying_to)
        } else {
            damus_state.drafts.post = NSMutableAttributedString(string: "")
        }

        dismiss()
    }

    var is_post_empty: Bool {
        return post.string.allSatisfy { $0.isWhitespace }
    }
    
    var ImageButton: some View {
        Button(action: {
            attach_media = true
        }, label: {
            Image(systemName: "photo")
        })
    }
    
    var AttachmentBar: some View {
        HStack(alignment: .center) {
            ImageButton
                .disabled(image_upload.progress != nil)
        }
    }
    
    var PostButton: some View {
        Button(NSLocalizedString("Post", comment: "Button to post a note.")) {
            showPrivateKeyWarning = contentContainsPrivateKey(self.post.string)

            if !showPrivateKeyWarning {
                self.send_post()
            }
        }
        .font(.system(size: 14, weight: .bold))
        .frame(width: 80, height: 30)
        .foregroundColor(.white)
        .background(LINEAR_GRADIENT)
        .clipShape(Capsule())
    }
    
    var TextEntry: some View {
        ZStack(alignment: .topLeading) {
            TextViewWrapper(attributedText: $post)
                .focused($focus)
                .textInputAutocapitalization(.sentences)
                .onChange(of: post) { _ in
                    if let replying_to {
                        damus_state.drafts.replies[replying_to] = post
                    } else {
                        damus_state.drafts.post = post
                    }
                }
            
            if post.string.isEmpty {
                Text(POST_PLACEHOLDER)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .foregroundColor(Color(uiColor: .placeholderText))
                    .allowsHitTesting(false)
            }
        }
    }
    
    var TopBar: some View {
        VStack {
            HStack(spacing: 5.0) {
                Button(NSLocalizedString("Cancel", comment: "Button to cancel out of posting a note.")) {
                    self.cancel()
                }
                .foregroundColor(.primary)
                
                if let error {
                    Text(error)
                        .foregroundColor(.red)
                }

                Spacer()

                if !is_post_empty {
                    PostButton
                }
            }
            
            if let progress = image_upload.progress {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
            }
        }
        .frame(height: 30)
        .padding([.top, .bottom], 4)
    }
    
    func append_url(_ url: String) {
        let uploadedImageURL = NSMutableAttributedString(string: url)
        let combinedAttributedString = NSMutableAttributedString()
        combinedAttributedString.append(post)
        if !post.string.hasSuffix(" ") {
            combinedAttributedString.append(NSAttributedString(string: " "))
        }
        combinedAttributedString.append(uploadedImageURL)
        
        // make sure we have a space at the end
        combinedAttributedString.append(NSAttributedString(string: " "))
        post = combinedAttributedString
    }
    
    func handle_upload(image: UIImage) {
        let uploader = get_image_uploader(damus_state.pubkey)
        
        Task.init {
            let res = await image_upload.start(img: image, uploader: uploader)
            
            switch res {
            case .success(let url):
                append_url(url)
                
            case .failed(let error):
                if let error {
                    self.error = error.localizedDescription
                } else {
                    self.error = "Error uploading image :("
                }
            }
            
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let searching = get_searching_string(post.string)
            
            TopBar
            
            HStack(alignment: .top) {
                ProfilePicView(pubkey: damus_state.pubkey, size: 45.0, highlight: .none, profiles: damus_state.profiles)
                
                TextEntry
            }
            .frame(maxHeight: searching == nil ? .infinity : 50)
            
            // This if-block observes @ for tagging
            if let searching {
                UserSearch(damus_state: damus_state, search: searching, post: $post)
                    .frame(maxHeight: .infinity)
            } else {
                Divider()
                    .padding([.bottom], 10)
                
                AttachmentBar
            }
        }
        .padding()
        .sheet(isPresented: $attach_media) {
            ImagePicker(sourceType: .photoLibrary) { img in
                handle_upload(image: img)
            }
        }
        .onAppear() {
            if let replying_to {
                if damus_state.drafts.replies[replying_to] == nil {
                    damus_state.drafts.post = NSMutableAttributedString(string: "")
                }
                if let p = damus_state.drafts.replies[replying_to] {
                    post = p
                }
            } else {
                post = damus_state.drafts.post
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.focus = true
            }
        }
        .onDisappear {
            if let replying_to, let reply = damus_state.drafts.replies[replying_to], reply.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                damus_state.drafts.replies.removeValue(forKey: replying_to)
            } else if replying_to == nil && damus_state.drafts.post.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                damus_state.drafts.post = NSMutableAttributedString(string : "")
            }
        }
        .alert(NSLocalizedString("Note contains \"nsec1\" private key. Are you sure?", comment: "Alert user that they might be attempting to paste a private key and ask them to confirm."), isPresented: $showPrivateKeyWarning, actions: {
            Button(NSLocalizedString("No", comment: "Button to cancel out of posting a note after being alerted that it looks like they might be posting a private key."), role: .cancel) {
                showPrivateKeyWarning = false
            }
            Button(NSLocalizedString("Yes, Post with Private Key", comment: "Button to proceed with posting a note even though it looks like they might be posting a private key."), role: .destructive) {
                self.send_post()
            }
        })
    }
}

func get_searching_string(_ post: String) -> String? {
    guard let last_word = post.components(separatedBy: .whitespacesAndNewlines).last else {
        return nil
    }
    
    guard last_word.count >= 2 else {
        return nil
    }
    
    guard last_word.first! == "@" else {
        return nil
    }
    
    // don't include @npub... strings
    guard last_word.count != 64 else {
        return nil
    }
    
    return String(last_word.dropFirst())
}

struct PostView_Previews: PreviewProvider {
    static var previews: some View {
        PostView(replying_to: nil, references: [], damus_state: test_damus_state())
    }
}
