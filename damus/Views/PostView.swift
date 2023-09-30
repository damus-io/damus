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

let POST_PLACEHOLDER = NSLocalizedString("Type your note here...", comment: "Text box prompt to ask user to type their note.")
let GHOST_CARET_VIEW_ID = "GhostCaret"
let DEBUG_SHOW_GHOST_CARET_VIEW: Bool = false

class TagModel: ObservableObject {
    var diff = 0
}

enum PostTarget {
    case none
    case user(Pubkey)
}

enum PostAction {
    case replying_to(NostrEvent)
    case quoting(NostrEvent)
    case posting(PostTarget)
    
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
    @State var references: [RefId] = []
    @State var filtered_pubkeys: Set<Pubkey> = []
    @State var focusWordAttributes: (String?, NSRange?) = (nil, nil)
    @State var newCursorIndex: Int?
    @State var caretRect: CGRect = CGRectNull
    @State var textHeight: CGFloat? = nil

    @State var mediaToUpload: MediaUpload? = nil
    
    @StateObject var image_upload: ImageUploadModel = ImageUploadModel()
    @StateObject var tagModel: TagModel = TagModel()

    let action: PostAction
    let damus_state: DamusState

    @Environment(\.presentationMode) var presentationMode

    func cancel() {
        notify(.post(.cancel))
        dismiss()
    }

    func dismiss() {
        self.presentationMode.wrappedValue.dismiss()
    }
    
    func send_post() {
        let refs = references.filter { ref in
            if case .pubkey(let pk) = ref, filtered_pubkeys.contains(pk) {
                return false
            }
            return true
        }
        let new_post = build_post(post: self.post, action: action, uploadedMedias: uploadedMedias, references: refs)

        notify(.post(.post(new_post)))

        clear_draft()

        dismiss()

    }

    var is_post_empty: Bool {
        return post.string.allSatisfy { $0.isWhitespace } && uploadedMedias.isEmpty
    }

    var uploading_disabled: Bool {
        return image_upload.progress != nil
    }

    var posting_disabled: Bool {
        return is_post_empty || uploading_disabled
    }
    
    // Returns a valid height for the text box, even when textHeight is not a number
    func get_valid_text_height() -> CGFloat {
        if let textHeight, textHeight.isFinite, textHeight > 0 {
            return textHeight
        }
        else {
            return 10
        }
    }
    
    var ImageButton: some View {
        Button(action: {
            attach_media = true
        }, label: {
            Image("images")
                .padding(6)
        })
    }
    
    var CameraButton: some View {
        Button(action: {
            attach_camera = true
        }, label: {
            Image("camera")
                .padding(6)
        })
    }
    
    var AttachmentBar: some View {
        HStack(alignment: .center) {
            ImageButton
            CameraButton
        }
        .disabled(uploading_disabled)
    }
    
    var PostButton: some View {
        Button(NSLocalizedString("Post", comment: "Button to post a note.")) {
            showPrivateKeyWarning = contentContainsPrivateKey(self.post.string)

            if !showPrivateKeyWarning {
                self.send_post()
            }
        }
        .disabled(posting_disabled)
        .font(.system(size: 14, weight: .bold))
        .frame(width: 80, height: 30)
        .foregroundColor(.white)
        .background(LINEAR_GRADIENT)
        .opacity(posting_disabled ? 0.5 : 1.0)
        .clipShape(Capsule())
    }
    
    func isEmpty() -> Bool {
        return self.uploadedMedias.count == 0 &&
            self.post.mutableString.trimmingCharacters(in: .whitespacesAndNewlines) ==
                initialString().mutableString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func initialString() -> NSMutableAttributedString {
        guard case .posting(let target) = action,
              case .user(let pubkey) = target,
              damus_state.pubkey != pubkey else {
            return .init(string: "")
        }
        
        let profile_txn = damus_state.profiles.lookup(id: pubkey)
        let profile = profile_txn.unsafeUnownedValue
        return user_tag_attr_string(profile: profile, pubkey: pubkey)
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
    
    func load_draft() -> Bool {
        guard let draft = load_draft_for_post(drafts: self.damus_state.drafts, action: self.action) else {
            self.post = NSMutableAttributedString("")
            self.uploadedMedias = []
            
            return false
        }
        
        self.uploadedMedias = draft.media
        self.post = draft.content
        return true
    }

    func post_changed(post: NSMutableAttributedString, media: [UploadedMedia]) {
        if let draft = load_draft_for_post(drafts: damus_state.drafts, action: action) {
            draft.content = post
            draft.media = media
        } else {
            let artifacts = DraftArtifacts(content: post, media: media)
            set_draft_for_post(drafts: damus_state.drafts, action: action, artifacts: artifacts)
        }
    }
    
    var TextEntry: some View {
        ZStack(alignment: .topLeading) {
            TextViewWrapper(attributedText: $post, textHeight: $textHeight, cursorIndex: newCursorIndex, getFocusWordForMention: { word, range in
                focusWordAttributes = (word, range)
                self.newCursorIndex = nil
            }, updateCursorPosition: { newCursorIndex in
                self.newCursorIndex = newCursorIndex
            }, onCaretRectChange: { uiView in
                // When the caret position changes, we change the `caretRect` in our state, so that our ghost caret will follow our caret
                if let selectedStartRange = uiView.selectedTextRange?.start {
                    DispatchQueue.main.async {
                        caretRect = uiView.caretRect(for: selectedStartRange)
                    }
                }
            })
                .environmentObject(tagModel)
                .focused($focus)
                .textInputAutocapitalization(.sentences)
                .onChange(of: post) { p in
                    post_changed(post: p, media: uploadedMedias)
                }
                // Set a height based on the text content height, if it is available and valid
                .frame(height: get_valid_text_height())
            
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
        let uploader = damus_state.settings.default_media_uploader
        Task {
            let img = getImage(media: media)
            print("img size w:\(img.size.width) h:\(img.size.height)")
            async let blurhash = calculate_blurhash(img: img)
            let res = await image_upload.start(media: media, uploader: uploader, keypair: damus_state.keypair)
            
            switch res {
            case .success(let url):
                guard let url = URL(string: url) else {
                    self.error = "Error uploading image :("
                    return
                }
                let blurhash = await blurhash
                let meta = blurhash.map { bh in calculate_image_metadata(url: url, img: img, blurhash: bh) }
                let uploadedMedia = UploadedMedia(localURL: media.localURL, uploadedURL: url, representingImage: img, metadata: meta)
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
    
    var multiply_factor: CGFloat {
        if case .quoting = action {
            return 0.4
        } else if !uploadedMedias.isEmpty {
            return 0.2
        } else {
            return 1.0
        }
    }
    
    func Editor(deviceSize: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if(caretRect != CGRectNull) {
                GhostCaret
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ProfilePicView(pubkey: damus_state.pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                    
                    TextEntry
                }
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
    }
    
    // The GhostCaret is a vertical projection of the editor's caret that should sit beside the editor.
    // The purpose of this view is create a reference point that we can scroll our ScrollView into
    // This is necessary as a bridge to communicate between:
    // - The UIKit-based UITextView (which has the caret position)
    // - and the SwiftUI-based ScrollView/ScrollReader (where scrolling commands can only be done via the SwiftUI "ID" parameter
    var GhostCaret: some View {
        Rectangle()
            .foregroundStyle(DEBUG_SHOW_GHOST_CARET_VIEW ? .cyan : .init(red: 0, green: 0, blue: 0, opacity: 0))
            .frame(
                width: DEBUG_SHOW_GHOST_CARET_VIEW ? caretRect.width : 0,
                height: caretRect.height)
            // Use padding to vertically align our ghost caret with our actual text caret.
            // Note: Programmatic scrolling cannot be done with the `.position` modifier.
            // Experiments revealed that the scroller ignores the position modifier.
            .padding(.top, caretRect.origin.y)
            .id(GHOST_CARET_VIEW_ID)
            .disabled(true)
    }
    
    func fill_target_content(target: PostTarget) {
        self.post = initialString()
        self.tagModel.diff = post.string.count
    }

    var pubkeys: [Pubkey] {
        self.references.reduce(into: [Pubkey]()) { pks, ref in
            guard case .pubkey(let pk) = ref else {
                return
            }

            pks.append(pk)
        }
    }

    var body: some View {
        GeometryReader { (deviceSize: GeometryProxy) in
            VStack(alignment: .leading, spacing: 0) {
                let searching = get_searching_string(focusWordAttributes.0)
                let searchingIsNil = searching == nil
                
                TopBar
                
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(alignment: .leading) {
                            if case .replying_to(let replying_to) = self.action {
                                ReplyView(replying_to: replying_to, damus: damus_state, original_pubkeys: pubkeys, filtered_pubkeys: $filtered_pubkeys)
                            }
                            
                            Editor(deviceSize: deviceSize)
                        }
                    }
                    .frame(maxHeight: searching == nil ? deviceSize.size.height : 70)
                    .onAppear {
                        scroll_to_event(scroller: scroller, id: "post", delay: 1.0, animate: true, anchor: .top)
                    }
                    // Note: The scroll commands below are specific because there seems to be quirk with ScrollReader where sending it to the exact same position twice resets its scroll position.
                    .onChange(of: caretRect.origin.y, perform: { newValue in
                        scroller.scrollTo(GHOST_CARET_VIEW_ID)
                    })
                    .onChange(of: searchingIsNil, perform: { newValue in
                        scroller.scrollTo(GHOST_CARET_VIEW_ID)
                    })
                }
                
                // This if-block observes @ for tagging
                if let searching {
                    UserSearch(damus_state: damus_state, search: searching, focusWordAttributes: $focusWordAttributes, newCursorIndex: $newCursorIndex, post: $post)
                        .frame(maxHeight: .infinity)
                        .environmentObject(tagModel)
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
                ImagePicker(uploader: damus_state.settings.default_media_uploader, sourceType: .photoLibrary, pubkey: damus_state.pubkey, image_upload_confirm: $image_upload_confirm) { img in
                    self.mediaToUpload = .image(img)
                } onVideoPicked: { url in
                    self.mediaToUpload = .video(url)
                }
                .alert(NSLocalizedString("Are you sure you want to upload this media?", comment: "Alert message asking if the user wants to upload media."), isPresented: $image_upload_confirm) {
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
                
                ImagePicker(uploader: damus_state.settings.default_media_uploader, sourceType: .camera, pubkey: damus_state.pubkey, image_upload_confirm: $image_upload_confirm) { img in
                    self.mediaToUpload = .image(img)
                } onVideoPicked: { url in
                    self.mediaToUpload = .video(url)
                }
                .alert(NSLocalizedString("Are you sure you want to upload this media?", comment: "Alert message asking if the user wants to upload media."), isPresented: $image_upload_confirm) {
                    Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                        if let mediaToUpload {
                            self.handle_upload(media: mediaToUpload)
                            self.attach_camera = false
                        }
                    }
                    Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
                }
            }
            .onAppear() {
                let loaded_draft = load_draft()
                
                switch action {
                case .replying_to(let replying_to):
                    references = gather_reply_ids(our_pubkey: damus_state.pubkey, from: replying_to)
                case .quoting(let quoting):
                    references = gather_quote_ids(our_pubkey: damus_state.pubkey, from: quoting)
                case .posting(let target):
                    guard !loaded_draft else { break }
                    
                    fill_target_content(target: target)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.focus = true
                }
            }
            .onDisappear {
                if isEmpty() {
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

func get_searching_string(_ word: String?) -> String? {
    guard let word = word else {
        return nil
    }

    guard word.count >= 2 else {
        return nil
    }
    
    guard let firstCharacter = word.first,
          firstCharacter == "@" else {
        return nil
    }
    
    // don't include @npub... strings
    guard word.count != 64 else {
        return nil
    }
    
    return String(word.dropFirst())
}

struct PostView_Previews: PreviewProvider {
    static var previews: some View {
        PostView(action: .posting(.none), damus_state: test_damus_state)
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
                                        Label(NSLocalizedString("Copy URL", comment: "Label for button in context menu to copy URL of the selected uploaded media asset."), image: "copy")
                                    }
                                }
                            }
                        Image("close-circle")
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
    let metadata: ImageMetadata?
}


func set_draft_for_post(drafts: Drafts, action: PostAction, artifacts: DraftArtifacts) {
    switch action {
    case .replying_to(let ev):
        drafts.replies[ev] = artifacts
    case .quoting(let ev):
        drafts.quotes[ev] = artifacts
    case .posting:
        drafts.post = artifacts
    }
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


func build_post(post: NSMutableAttributedString, action: PostAction, uploadedMedias: [UploadedMedia], references: [RefId]) -> NostrPost {
    post.enumerateAttributes(in: NSRange(location: 0, length: post.length), options: []) { attributes, range, stop in
        if let link = attributes[.link] as? String {
            let normalized_link: String
            if link.hasPrefix("damus:nostr:") {
                // Replace damus:nostr: URI prefix with nostr: since the former is for internal navigation and not meant to be posted.
                normalized_link = String(link.dropFirst(6))
            } else {
                normalized_link = link
            }

            // Add zero-width space in case text preceding the mention is not a whitespace.
            // In the case where the character preceding the mention is a whitespace, the added zero-width space will be stripped out.
            post.replaceCharacters(in: range, with: "\(normalized_link)")
        }
    }


    var content = post.string
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

    let imagesString = uploadedMedias.map { $0.uploadedURL.absoluteString }.joined(separator: " ")

    let img_meta_tags = uploadedMedias.compactMap { $0.metadata?.to_tag() }

    if !imagesString.isEmpty {
        content.append(" " + imagesString + " ")
    }

    if case .quoting(let ev) = action {
        content.append(" nostr:" + bech32_note_id(ev.id))
    }

    return NostrPost(content: content, references: references, kind: .text, tags: img_meta_tags)
}
