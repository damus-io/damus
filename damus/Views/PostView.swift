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
    case highlighting(HighlightContentDraft)
    
    var ev: NostrEvent? {
        switch self {
            case .replying_to(let ev):
                return ev
            case .quoting(let ev):
                return ev
            case .posting:
                return nil
            case .highlighting:
                return nil
        }
    }
}

struct PostView: View {
    @State var post: NSMutableAttributedString = NSMutableAttributedString()
    @FocusState var focus: Bool
    @State var attach_media: Bool = false
    @State var attach_camera: Bool = false
    @State var error: String? = nil
    @State var uploadedMedias: [UploadedMedia] = []
    @State var image_upload_confirm: Bool = false
    @State var references: [RefId] = []
    @State var filtered_pubkeys: Set<Pubkey> = []
    @State var focusWordAttributes: (String?, NSRange?) = (nil, nil)
    @State var newCursorIndex: Int?
    @State var textHeight: CGFloat? = nil

    @State var preUploadedMedia: PreUploadedMedia? = nil
    
    @StateObject var image_upload: ImageUploadModel = ImageUploadModel()
    @StateObject var tagModel: TagModel = TagModel()
    
    @State private var current_placeholder_index = 0

    let action: PostAction
    let damus_state: DamusState
    let prompt_view: (() -> AnyView)?
    let placeholder_messages: [String]
    let initial_text_suffix: String?
    
    init(
        action: PostAction,
        damus_state: DamusState,
        prompt_view: (() -> AnyView)? = nil,
        placeholder_messages: [String]? = nil,
        initial_text_suffix: String? = nil
    ) {
        self.action = action
        self.damus_state = damus_state
        self.prompt_view = prompt_view
        self.placeholder_messages = placeholder_messages ?? [POST_PLACEHOLDER]
        self.initial_text_suffix = initial_text_suffix
    }

    @Environment(\.dismiss) var dismiss

    func cancel() {
        notify(.post(.cancel))
        dismiss()
    }
    
    func send_post() {
        // don't add duplicate pubkeys but retain order
        var pkset = Set<Pubkey>()

        // we only want pubkeys really
        let pks = references.reduce(into: Array<Pubkey>()) { acc, ref in
            guard case .pubkey(let pk) = ref else {
                return
            }
            
            if pkset.contains(pk) || filtered_pubkeys.contains(pk) {
                return
            }

            pkset.insert(pk)
            acc.append(pk)
        }

        let new_post = build_post(state: damus_state, post: self.post, action: action, uploadedMedias: uploadedMedias, pubkeys: pks)

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
        switch action {
            case .highlighting(_):
                return false
            default:
                return is_post_empty || uploading_disabled
        }
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
        HStack(alignment: .center, spacing: 15) {
            ImageButton
            CameraButton
        }
        .disabled(uploading_disabled)
    }
    
    var PostButton: some View {
        Button(NSLocalizedString("Post", comment: "Button to post a note.")) {
            self.send_post()
        }
        .disabled(posting_disabled)
        .opacity(posting_disabled ? 0.5 : 1.0)
        .bold()
        .buttonStyle(GradientButtonStyle(padding: 10))
        
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
        let profile = profile_txn?.unsafeUnownedValue
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
            case .highlighting(let draft):
                damus_state.drafts.highlights.removeValue(forKey: draft.source)
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
            TextViewWrapper(
                attributedText: $post,
                textHeight: $textHeight,
                initialTextSuffix: initial_text_suffix, 
                cursorIndex: newCursorIndex,
                getFocusWordForMention: { word, range in
                    focusWordAttributes = (word, range)
                    self.newCursorIndex = nil
                }, 
                updateCursorPosition: { newCursorIndex in
                    self.newCursorIndex = newCursorIndex
                }
            )
                .environmentObject(tagModel)
                .focused($focus)
                .textInputAutocapitalization(.sentences)
                .onChange(of: post) { p in
                    post_changed(post: p, media: uploadedMedias)
                }
                // Set a height based on the text content height, if it is available and valid
                .frame(height: get_valid_text_height())
            
            if post.string.isEmpty {
                Text(self.placeholder_messages[self.current_placeholder_index])
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .foregroundColor(Color(uiColor: .placeholderText))
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Schedule a timer to switch messages every 3 seconds
            Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { timer in
                withAnimation {
                    self.current_placeholder_index = (self.current_placeholder_index + 1) % self.placeholder_messages.count
                }
            }
        }
    }
    
    var TopBar: some View {
        VStack {
            HStack(spacing: 5.0) {
                Button(action: {
                    self.cancel()
                }, label: {
                    Text("Cancel", comment: "Button to cancel out of posting a note.")
                        .padding(10)
                })
                .buttonStyle(NeutralButtonStyle())
                
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
            
            Divider()
                .foregroundColor(DamusColors.neutral3)
                .padding(.top, 5)
        }
        .frame(height: 30)
        .padding()
        .padding(.top, 15)
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
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ProfilePicView(pubkey: damus_state.pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                    
                    VStack(alignment: .leading) {
                        if let prompt_view {
                            prompt_view()
                        }
                        TextEntry
                    }
                }
                .id("post")
                
                PVImageCarouselView(media: $uploadedMedias, deviceWidth: deviceSize.size.width)
                    .onChange(of: uploadedMedias) { media in
                        post_changed(post: post, media: media)
                    }
                
                if case .quoting(let ev) = action {
                    BuilderEventView(damus: damus_state, event: ev)
                }
                else if case .highlighting(let draft) = action {
                    HighlightDraftContentView(draft: draft)
                }
            }
            .padding(.horizontal)
        }
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

                TopBar
                
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(alignment: .leading) {
                            if case .replying_to(let replying_to) = self.action {
                                ReplyView(replying_to: replying_to, damus: damus_state, original_pubkeys: pubkeys, filtered_pubkeys: $filtered_pubkeys)
                            }
                            
                            Editor(deviceSize: deviceSize)
                                .padding(.top, 5)
                        }
                    }
                    .frame(maxHeight: searching == nil ? deviceSize.size.height : 70)
                    .onAppear {
                        scroll_to_event(scroller: scroller, id: "post", delay: 1.0, animate: true, anchor: .top)
                    }
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
            .background(DamusColors.adaptableWhite.edgesIgnoringSafeArea(.all))
            .sheet(isPresented: $attach_media) {
                MediaPicker(image_upload_confirm: $image_upload_confirm){ media in
                    self.preUploadedMedia = media
                }
                .alert(NSLocalizedString("Are you sure you want to upload this media?", comment: "Alert message asking if the user wants to upload media."), isPresented: $image_upload_confirm) {
                    Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                        if let mediaToUpload = generateMediaUpload(preUploadedMedia) {
                            self.handle_upload(media: mediaToUpload)
                            self.attach_media = false
                        }
                    }
                    Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
                }
            }
            .sheet(isPresented: $attach_camera) {
                CameraController(uploader: damus_state.settings.default_media_uploader) {
                    self.attach_camera = false
                    self.attach_media = true
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
                    case .highlighting(let draft):
                        references = [draft.source.ref()]
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
    case .highlighting(let draft):
        drafts.highlights[draft.source] = artifacts
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
    case .highlighting(let draft):
        return drafts.highlights[draft.source]
    }
}

private func isAlphanumeric(_ char: Character) -> Bool {
    return char.isLetter || char.isNumber
}

func nip10_reply_tags(replying_to: NostrEvent, keypair: Keypair) -> [[String]] {
    guard let nip10 = replying_to.thread_reply() else {
        // we're replying to a post that isn't in a thread,
        // just add a single reply-to-root tag
        return [["e", replying_to.id.hex(), "", "root"]]
    }

    // otherwise use the root tag from the parent's nip10 reply and include the note
    // that we are replying to's note id.
    let tags = [
        ["e", nip10.root.note_id.hex(), nip10.root.relay ?? "", "root"],
        ["e", replying_to.id.hex(), "", "reply"]
    ]

    return tags
}

func build_post(state: DamusState, post: NSMutableAttributedString, action: PostAction, uploadedMedias: [UploadedMedia], pubkeys: [Pubkey]) -> NostrPost {
    post.enumerateAttributes(in: NSRange(location: 0, length: post.length), options: []) { attributes, range, stop in
        if let link = attributes[.link] as? String {
            let nextCharIndex = range.upperBound
            if nextCharIndex < post.length,
               let nextChar = post.attributedSubstring(from: NSRange(location: nextCharIndex, length: 1)).string.first,
               isAlphanumeric(nextChar) {
                post.insert(NSAttributedString(string: " "), at: nextCharIndex)
            }

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

    if !imagesString.isEmpty {
        content.append(" " + imagesString + " ")
    }

    var tags: [[String]] = []

    switch action {
        case .replying_to(let replying_to):
            // start off with the reply tags
            tags = nip10_reply_tags(replying_to: replying_to, keypair: state.keypair)

        case .quoting(let ev):
            content.append(" nostr:" + bech32_note_id(ev.id))

            if let quoted_ev = state.events.lookup(ev.id) {
                tags.append(["p", quoted_ev.pubkey.hex()])
            }
        case .posting(let postTarget):
            break
        case .highlighting(let draft):
            break
    }
    
    // include pubkeys
    tags += pubkeys.map { pk in
        ["p", pk.hex()]
    }

    // append additional tags
    tags += uploadedMedias.compactMap { $0.metadata?.to_tag() }
    
    switch action {
        case .highlighting(let draft):
            tags.append(contentsOf: draft.source.tags())
            if !(content.isEmpty || content.allSatisfy { $0.isWhitespace })  {
                tags.append(["comment", content])
            }
            return NostrPost(content: draft.selected_text, kind: .highlight, tags: tags)
        default:
            break
    }

    return NostrPost(content: content, kind: .text, tags: tags)
}

