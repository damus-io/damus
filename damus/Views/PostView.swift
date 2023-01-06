//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-04-03.
//

import SwiftUI
import Foundation
import Kingfisher

enum NostrPostResult {
    case post(NostrPost)
    case cancel
}

let POST_PLACEHOLDER = NSLocalizedString("Type your post here...", comment: "Text box prompt to ask user to type their post.")

struct PostView: View {
    @State var post: String = ""
    
    @State var image_host_error: Error?
    @State var show_image_host_error = false
    @State var showing_image_picker = false
    @State var image: Image?
    @State var image_data: Data?
    @State var image_url: URL?
    @State var showSelectImageHostView: Bool = false
    @State var is_posting: Bool = false {
        didSet {
            if is_posting {
                send_post()
            }
        }
    }
    @ObservedObject var user_settings = UserSettingsStore()

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
        if let image_url = image_url { post += " " + image_url.absoluteString }
        let content = self.post.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let new_post = NostrPost(content: content, references: references, kind: kind)

        NotificationCenter.default.post(name: .post, object: NostrPostResult.post(new_post))
        dismiss()
    }

    var is_post_empty: Bool {
        return post.allSatisfy { $0.isWhitespace } && image_data == nil
    }
    
    var can_post: Bool {
        if is_post_empty { return false }
        if image_data != nil && image_url == nil { return false }
        return true
    }
    
    func choose_image() {
        showing_image_picker = true
    }
    
    func load_image() {
        guard let uiimage = UIImage(data: image_data!) else { return }
        self.image = Image(uiImage: uiimage)
    }
    
    func upload_image() {
        self.image_url = nil
        if let image_data = image_data {
            let image_host = user_settings.default_image_host
            image_host.uploadImage(image_data: image_data) { result in
                switch result {
                    case .success(let image_url):
                        // do something with the json data
                        self.image_url = image_url
                    case .failure(let error):
                        // handle the error
                        self.image_host_error = error
                        self.show_image_host_error = true
                        self.image = nil
                        self.image_data = nil
                        self.image_url = nil
                        print(error)
                }
            }
        }
    }

    var body: some View {
        VStack {
            HStack {
                Button("Cancel") {
                    self.cancel()
                }
                .foregroundColor(.primary)

                Spacer()

                if can_post {
                    if self.is_posting {
                        ProgressView()
                    } else {
                        Button("Post") {
                            self.is_posting = true
                        }
                    }
                } else if image_data != nil && image_url == nil {
                    ProgressView()
                }
            }
            .padding([.top, .bottom], 4)

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
            .frame(maxHeight: 250)
            
            if image != nil || image_url != nil {
                ZStack {
                    image?
                        .resizable()
                    if self.image_url != nil {
                        KFAnimatedImage(self.image_url)
                            .onSuccess({ result in
                                self.image = nil
                            })
                    }
                }
                .scaledToFit()
                .frame(maxHeight: 100)
            }
            
            if replying_to == nil {
                Divider()
                HStack {
                    Button(action: {
                        self.choose_image()
                    }) {
                        Image(systemName: "photo")
                            .foregroundColor(.primary)
                    }
                    .onChange(of: image_data) { _ in
                        if image_data != nil {
                            load_image()
                            upload_image()
                        }
                    }
                    .sheet(isPresented: $showing_image_picker) {
                        ImagePicker(image_data: $image_data)
                    }
                    Spacer()
                }
                .padding([.top, .bottom], 4)
                Spacer()
            }
        }
        .onAppear() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.focus = true
            }
        }
        .padding()
        .alert(isPresented: $show_image_host_error) {
            Alert(title: Text("Sorry"), message: Text("There was a problem uploading your image."), dismissButton: .default(Text("OK")))
        }
    }
}

