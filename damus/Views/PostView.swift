//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-04-03.
//

import SwiftUI
import AVFoundation

enum NostrPostResult {
    case post(NostrPost)
    case cancel
}

let POST_PLACEHOLDER = NSLocalizedString("Type your post here...", comment: "Text box prompt to ask user to type their post.")

enum PostAction {
    case replying_to(NostrEvent)
    case quoting(NostrEvent)
    case posting
    
    var ev: NostrEvent? {
        switch self {
        case .replying_to(let ev):
            return ev
        case .quoting(let ev):
            return ev
        case .posting:
            return nil
        }
    }
}

struct PostView: View {
    @State var post: NSMutableAttributedString = NSMutableAttributedString()
    @FocusState var focus: Bool
    @State var showPrivateKeyWarning: Bool = false
    @State var attach_media: Bool = false
    @State var attach_camera: Bool = false
    @State var error: String? = nil
    @State var uploadedMedias: [UploadedMedia] = []
    @State var image_upload_confirm: Bool = false
    @State var originalReferences: [ReferencedId] = []
    @State var references: [ReferencedId] = []

    @State var mediaToUpload: MediaUpload? = nil
    
    @StateObject var image_upload: ImageUploadModel = ImageUploadModel()

    let action: PostAction
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

        if case .replying_to(let ev) = action, ev.known_kind == .chat {
            kind = .chat
        }

        post.enumerateAttributes(in: NSRange(location: 0, length: post.length), options: []) { attributes, range, stop in
            if let link = attributes[.link] as? String {
                post.replaceCharacters(in: range, with: link)
            }
        }

        var content = self.post.string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        let imagesString = uploadedMedias.map { $0.uploadedURL.absoluteString }.joined(separator: " ")

        content.append(" " + imagesString + " ")

        if case .quoting(let ev) = action, let id = bech32_note_id(ev.id) {
            content.append(" nostr:" + id)
        }
        
        let new_post = NostrPost(content: content, references: references, kind: kind)

        NotificationCenter.default.post(name: .post, object: NostrPostResult.post(new_post))
        
        clear_draft()

        dismiss()
    }

    var is_post_empty: Bool {
        return post.string.allSatisfy { $0.isWhitespace } && uploadedMedias.isEmpty
    }
    
    var ImageButton: some View {
        Button(action: {
            attach_media = true
        }, label: {
            Image(systemName: "photo")
                .padding(6)
        })
    }
    
    var CameraButton: some View {
        Button(action: {
            attach_camera = true
        }, label: {
            Image(systemName: "camera")
                .padding(6)
        })
    }
    
    var AttachmentBar: some View {
        HStack(alignment: .center) {
            ImageButton
            CameraButton
        }
        .disabled(image_upload.progress != nil)
    }
    
    var PostButton: some View {
        Button(NSLocalizedString("Post", comment: "Button to post a note.")) {
            showPrivateKeyWarning = contentContainsPrivateKey(self.post.string)

            if !showPrivateKeyWarning {
                self.send_post()
            }
        }
        .disabled(is_post_empty)
        .font(.system(size: 14, weight: .bold))
        .frame(width: 80, height: 30)
        .foregroundColor(.white)
        .background(LINEAR_GRADIENT)
        .opacity(is_post_empty ? 0.5 : 1.0)
        .clipShape(Capsule())
    }
    
    var isEmpty: Bool {
        self.uploadedMedias.count == 0 &&
        self.post.mutableString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func clear_draft() {
        switch action {
            case .replying_to(let replying_to):
                damus_state.drafts.replies.removeValue(forKey: replying_to)
            case .quoting(let quoting):
                damus_state.drafts.quotes.removeValue(forKey: quoting)
            case .posting:
                damus_state.drafts.post = nil
        }

    }
    
    func load_draft() {
        guard let draft = load_draft_for_post(drafts: self.damus_state.drafts, action: self.action) else {
            self.post = NSMutableAttributedString("")
            self.uploadedMedias = []
            return
        }
        
        self.uploadedMedias = draft.media
        self.post = draft.content
    }
    
    func post_changed(post: NSMutableAttributedString, media: [UploadedMedia]) {
        switch action {
        case .replying_to(let ev):
            if let draft = damus_state.drafts.replies[ev] {
                draft.content = post
                draft.media = media
            } else {
                damus_state.drafts.replies[ev] = DraftArtifacts(content: post, media: media)
            }
        case .quoting(let ev):
            if let draft = damus_state.drafts.quotes[ev] {
                draft.content = post
                draft.media = media
            } else {
                damus_state.drafts.quotes[ev] = DraftArtifacts(content: post, media: media)
            }
        case .posting:
            if let draft = damus_state.drafts.post {
                draft.content = post
                draft.media = media
            } else {
                damus_state.drafts.post = DraftArtifacts(content: post, media: media)
            }
        }
    }
    
    var TextEntry: some View {
        ZStack(alignment: .topLeading) {
            TextViewWrapper(attributedText: $post)
                .focused($focus)
                .textInputAutocapitalization(.sentences)
                .onChange(of: post) { p in
                    post_changed(post: p, media: uploadedMedias)
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

                PostButton
            }
            
            if let progress = image_upload.progress {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
            }
        }
        .frame(height: 30)
        .padding()
    }
    
    func handle_upload(media: MediaUpload) {
        let uploader = get_media_uploader(damus_state.pubkey)
        Task.init {
            let img = getImage(media: media)
            let res = await image_upload.start(media: media, uploader: uploader)
            
            switch res {
            case .success(let url):
                guard let url = URL(string: url) else {
                    self.error = "Error uploading image :("
                    return
                }
                let uploadedMedia = UploadedMedia(localURL: media.localURL, uploadedURL: url, representingImage: img)
                uploadedMedias.append(uploadedMedia)
                
            case .failed(let error):
                if let error {
                    self.error = error.localizedDescription
                } else {
                    self.error = "Error uploading image :("
                }
            }
            
        }
    }
    
    var has_artifacts: Bool {
        if case .quoting = action {
            return true
        }
        return !uploadedMedias.isEmpty
    }
    
    func Editor(deviceSize: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ProfilePicView(pubkey: damus_state.pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles)
                
                TextEntry
            }
            .frame(height: has_artifacts ? deviceSize.size.height*0.4 : deviceSize.size.height)
            .id("post")
                
            PVImageCarouselView(media: $uploadedMedias, deviceWidth: deviceSize.size.width)
                .onChange(of: uploadedMedias) { media in
                    post_changed(post: post, media: media)
                }
            
            if case .quoting(let ev) = action {
                BuilderEventView(damus: damus_state, event: ev)
            }
        }
        .padding(.horizontal)
    }
    
    var body: some View {
        GeometryReader { (deviceSize: GeometryProxy) in
            VStack(alignment: .leading, spacing: 0) {

                let searching = get_searching_string(post.string)
                
                TopBar
                
                ScrollViewReader { scroller in
                    ScrollView {
                        if case .replying_to(let replying_to) = self.action {
                            ReplyView(replying_to: replying_to, damus: damus_state, originalReferences: $originalReferences, references: $references)
                        }
                        
                        Editor(deviceSize: deviceSize)
                    }
                    .frame(maxHeight: searching == nil ? .infinity : 70)
                    .onAppear {
                        scroll_to_event(scroller: scroller, id: "post", delay: 1.0, animate: true, anchor: .top)
                    }
                }
                
                // This if-block observes @ for tagging
                if let searching {
                    UserSearch(damus_state: damus_state, search: searching, post: $post)
                        .frame(maxHeight: .infinity)
                } else {
                    Divider()
                    VStack(alignment: .leading) {
                        AttachmentBar
                            .padding(.vertical, 5)
                            .padding(.horizontal)
                    }
                }
            }
            .sheet(isPresented: $attach_media) {
                ImagePicker(sourceType: .photoLibrary, pubkey: damus_state.pubkey, image_upload_confirm: $image_upload_confirm) { img in
                    self.mediaToUpload = .image(img)
                } onVideoPicked: { url in
                    self.mediaToUpload = .video(url)
                }
                .alert(NSLocalizedString("Are you sure you want to upload this image?", comment: "Alert message asking if the user wants to upload an image."), isPresented: $image_upload_confirm) {
                    Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                        if let mediaToUpload {
                            self.handle_upload(media: mediaToUpload)
                            self.attach_media = false
                        }
                    }
                    Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
                }
            }
            .sheet(isPresented: $attach_camera) {
                // image_upload_confirm isn't handled here, I don't know we need to display it here too tbh
                ImagePicker(sourceType: .camera, pubkey: damus_state.pubkey, image_upload_confirm: $image_upload_confirm) { img in
                    handle_upload(media: .image(img))
                } onVideoPicked: { url in
                    handle_upload(media: .video(url))
                }
            }
            .onAppear() {
                load_draft()
                
                switch action {
                case .replying_to(let replying_to):
                    references = gather_reply_ids(our_pubkey: damus_state.pubkey, from: replying_to)
                    originalReferences = references
                case .quoting(let quoting):
                    references = gather_quote_ids(our_pubkey: damus_state.pubkey, from: quoting)
                    originalReferences = references
                case .posting:
                    break
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.focus = true
                }
            }
            .onDisappear {
                if isEmpty {
                    clear_draft()
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
        PostView(action: .posting, damus_state: test_damus_state())
    }
}

struct PVImageCarouselView: View {
    @Binding var media: [UploadedMedia]

    let deviceWidth: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(media.map({$0.representingImage}), id: \.self) { image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: media.count == 1 ? deviceWidth*0.8 : 250, height: media.count == 1 ? 400 : 250)
                            .cornerRadius(10)
                            .padding()
                            .contextMenu {
                                if let uploadedURL = media.first(where: { $0.representingImage == image })?.uploadedURL {
                                    Button(action: {
                                        UIPasteboard.general.string = uploadedURL.absoluteString
                                    }) {
                                        Label("Copy URL", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .padding(20)
                            .shadow(radius: 5)
                            .onTapGesture {
                                if let index = media.map({$0.representingImage}).firstIndex(of: image) {
                                    media.remove(at: index)
                                }
                            }
                    }
                }
            }
            .padding()
        }
    }
}

fileprivate func getImage(media: MediaUpload) -> UIImage {
    var uiimage: UIImage = UIImage()
    if media.is_image {
        // fetch the image data
        if let data = try? Data(contentsOf: media.localURL) {
            uiimage = UIImage(data: data) ?? UIImage()
        }
    } else {
        let asset = AVURLAsset(url: media.localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTimeMake(value: 1, timescale: 60) // get the thumbnail image at the 1st second
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            uiimage = UIImage(cgImage: cgImage)
        } catch {
            print("No thumbnail: \(error)")
        }
        // create a play icon on the top to differentiate if media upload is image or a video, gif is an image
        let playIcon = UIImage(systemName: "play.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        let size = uiimage.size
        let scale = UIScreen.main.scale
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        uiimage.draw(at: .zero)
        let playIconSize = CGSize(width: 60, height: 60)
        let playIconOrigin = CGPoint(x: (size.width - playIconSize.width) / 2, y: (size.height - playIconSize.height) / 2)
        playIcon?.draw(in: CGRect(origin: playIconOrigin, size: playIconSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        uiimage = newImage ?? UIImage()
    }
    return uiimage
}

struct UploadedMedia: Equatable {
    let localURL: URL
    let uploadedURL: URL
    let representingImage: UIImage
}


func load_draft_for_post(drafts: Drafts, action: PostAction) -> DraftArtifacts? {
    switch action {
    case .replying_to(let ev):
        return drafts.replies[ev]
    case .quoting(let ev):
        return drafts.quotes[ev]
    case .posting:
        return drafts.post
    }
}
