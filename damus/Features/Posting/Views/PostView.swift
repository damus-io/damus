//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-04-03.
//

import SwiftUI
import AVKit
import Kingfisher

enum NostrPostResult {
    case post(NostrPost)
    /// A **private reply**: the same post the public path would have signed, plus the note it
    /// privately answers.
    ///
    /// A separate case rather than a flag on ``post(_:)`` because the two produce entirely different
    /// things — a signed kind 1 on one side, a pair of gift wraps on the other — and the branch
    /// belongs here, in the post action, rather than inside `NostrPost.to_event`. A private reply
    /// never becomes a ``NostrEvent`` at all, and keeping it out of the type the public egress path
    /// speaks is what makes that a property of the code rather than of a runtime guard.
    ///
    /// The parent travels with the post because it is the audience: a private reply is addressed to
    /// its author and to nobody else.
    case privateReply(NostrPost, replyingTo: NostrEvent)
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
    case sharing(ShareContent)
    
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
            case .sharing(_):
                return nil
        }
    }
}

@MainActor
struct PostView: View {
    
    @State var post: NSMutableAttributedString = NSMutableAttributedString()
    @StateObject private var voice: VoiceComposerModel
    @State private var postTextAfterDiscard = false
    @State var uploadedMedias: [UploadedMedia] = []
    @State var references: [RefId] = []
    /// Pubkeys that should be filtered out from the references
    ///
    /// For example, when replying to an event, the user can select which pubkey mentions they want to keep, and which ones to remove.
    @State var filtered_pubkeys: Set<Pubkey> = []
    
    @FocusState var focus: Bool
    @State var attach_media: Bool = false
    @State var attach_camera: Bool = false
    @State var attach_gif: Bool = false
    @State var error: String? = nil
    @State var image_upload_confirm: Bool = false
    @State var imagePastedFromPasteboard: PreUploadedMedia? = nil
    @State var imageUploadConfirmPasteboard: Bool = false
    /// Whether this reply will be sent privately — gift wrapped to the parent's author and to
    /// ourselves, and published nowhere else.
    ///
    /// Only ever meaningful when ``private_reply_recipient`` is non-nil; see ``can_reply_privately``.
    @State var is_private_reply: Bool = false
    @State var imageUploadConfirmDamusShare: Bool = false
    @State var focusWordAttributes: (String?, NSRange?) = (nil, nil)
    @State var newCursorIndex: Int?
    @State var textHeight: CGFloat? = nil
    /// Manages the auto-save logic for drafts.
    ///
    /// ## Implementation notes
    ///
    /// - This intentionally does _not_ use `@ObservedObject` or `@StateObject` because observing changes causes unwanted automatic scrolling to the text cursor on each save state update.
    var autoSaveModel: AutoSaveIndicatorView.AutoSaveViewModel

    @State var preUploadedMedia: [PreUploadedMedia] = []
    @State var mediaUploadUnderProgress: MediaUpload? = nil
    
    @StateObject var image_upload: ImageUploadModel = ImageUploadModel()
    @StateObject var tagModel: TagModel = TagModel()
    
    @State private var current_placeholder_index = 0
    @State private var uploadTasks: [Task<Void, Never>] = []
    @State private var profileFetchTasks: [Pubkey: Task<Void, Never>] = [:]

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
        self._voice = StateObject(wrappedValue: VoiceComposerModel(state: damus_state, action: action))
        self.damus_state = damus_state
        self.prompt_view = prompt_view
        self.placeholder_messages = placeholder_messages ?? [POST_PLACEHOLDER]
        self.initial_text_suffix = initial_text_suffix
        self.autoSaveModel = AutoSaveIndicatorView.AutoSaveViewModel(save: { await damus_state.drafts.save(damus_state: damus_state) })
    }

    @Environment(\.dismiss) var dismiss

    /// Text keeps its existing draft; audio must complete confirmed cleanup before dismissal.
    func cancel() {
        postTextAfterDiscard = false
        guard voice.requestDismiss() else { return }
        Task { if await voice.discardAndClose() { finishCancel() } }
    }

    private func finishCancel() {
        notify(.post(.cancel))
        cancelUploadTasks()
        cancelProfileFetchTasks()
        dismiss()
    }

    func cancelUploadTasks() {
        uploadTasks.forEach { $0.cancel() }
        uploadTasks.removeAll()
    }

    /// Cancels all pending profile fetch tasks.
    /// Called when the composer is dismissed to prevent background updates to a gone view.
    func cancelProfileFetchTasks() {
        profileFetchTasks.values.forEach { $0.cancel() }
        profileFetchTasks.removeAll()
    }

    // MARK: - Async Profile Fetch for Pasted npub/nprofile (Issue #2289)
    //
    // When a user pastes an npub or nprofile, we immediately create a mention link.
    // If the profile isn't in the local cache, the mention initially shows "@npub1abc...xyz".
    // We then fetch the profile from relays asynchronously and update the mention text
    // to show the human-readable name (e.g., "@jack") when it arrives.

    /// Fetches a profile from relays and updates any mentions in the post when it arrives.
    ///
    /// This enables pasted npub/nprofile identifiers to resolve to human-readable names
    /// even when the profile isn't in the local nostrdb cache. Uses `streamProfile` which
    /// queries relays and yields the profile when found.
    ///
    /// - Parameter pubkey: The public key to fetch the profile for
    func fetchProfileAndUpdateMention(pubkey: Pubkey) {
        // Avoid duplicate fetches for the same pubkey
        guard profileFetchTasks[pubkey] == nil else { return }

        let task = Task {
            // streamProfile yields profiles as they arrive from relays
            // yieldCached: false since we already checked the cache before calling this
            for await profile in await damus_state.nostrNetwork.profilesManager.streamProfile(pubkey: pubkey, yieldCached: false) {
                await MainActor.run {
                    updateMentionDisplayName(for: pubkey, profile: profile)
                }
                // Only need the first profile update
                break
            }

            await MainActor.run {
                profileFetchTasks.removeValue(forKey: pubkey)
            }
        }

        profileFetchTasks[pubkey] = task
    }

    /// Updates the display text for mentions matching the given pubkey.
    ///
    /// Finds all mention links with the matching `damus:nostr:` URL scheme and replaces
    /// the abbreviated "@npub1..." or "@nprofile1..." text with the resolved profile name.
    /// Preserves all existing attributes (link, styling) on the mention.
    ///
    /// Uses a two-pass approach to avoid undefined behavior from mutating while enumerating:
    /// 1. First pass: collect all matching ranges and their attributes
    /// 2. Second pass: replace ranges in reverse order to maintain valid indices
    ///
    /// - Parameters:
    ///   - pubkey: The public key whose mentions should be updated
    ///   - profile: The fetched profile containing the display name
    func updateMentionDisplayName(for pubkey: Pubkey, profile: Profile?) {
        let linkURL = "damus:nostr:\(pubkey.npub)"
        let newDisplayName = Profile.displayName(profile: profile, pubkey: pubkey).username.truncate(maxLength: 50)
        let newTagString = "@\(newDisplayName)"

        let mutablePost = NSMutableAttributedString(attributedString: post)

        // Pass 1: Collect matching ranges (avoid mutating while enumerating)
        var rangesToUpdate: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []

        mutablePost.enumerateAttribute(.link, in: NSRange(location: 0, length: mutablePost.length), options: []) { value, range, _ in
            // Extract link URL from either String or URL type
            let linkValue = (value as? String) ?? (value as? URL)?.absoluteString
            guard linkValue == linkURL else { return }

            // Only update if still showing abbreviated form (not already resolved)
            let currentText = mutablePost.attributedSubstring(from: range).string
            guard currentText.hasPrefix("@npub") || currentText.hasPrefix("@nprofile") else { return }

            // Preserve all attributes from the original range
            var collectedAttrs: [NSAttributedString.Key: Any] = [:]
            mutablePost.enumerateAttributes(in: range, options: []) { attrs, _, _ in
                collectedAttrs.merge(attrs) { _, new in new }
            }
            rangesToUpdate.append((range: range, attrs: collectedAttrs))
        }

        guard !rangesToUpdate.isEmpty else { return }

        // Pass 2: Replace in reverse order so earlier indices remain valid
        for (range, attrs) in rangesToUpdate.reversed() {
            let newAttrString = NSMutableAttributedString(string: newTagString)
            newAttrString.addAttributes(attrs, range: NSRange(location: 0, length: newAttrString.length))
            mutablePost.replaceCharacters(in: range, with: newAttrString)
        }

        // Update post without cursor adjustment - async updates shouldn't move user's cursor
        post = mutablePost
    }

    /// The person a private reply would be addressed to, or `nil` if this composer cannot make one.
    ///
    /// Non-nil only when replying, and only with a full keypair. A private *top-level* note is
    /// meaningless — there is no parent author to address it to — and the seal has to be signed by us,
    /// so a pubkey-only login cannot send one at all. Both conditions are answered here rather than at
    /// send time, so the toggle can never be flipped into a state that cannot send.
    ///
    /// Who it is, is ``NIP59/privateAudience(for:as:)`` — the same rule the builder uses,
    /// so the name in the lock row is the name the reply actually goes to. It is not simply the
    /// parent's author: replying to a private reply of our own continues the conversation with the
    /// person it was addressed to.
    var private_reply_recipient: Pubkey? {
        guard case .replying_to(let replying_to) = action else { return nil }
        guard let keypair = damus_state.keypair.to_full() else { return nil }
        return NIP59.privateAudience(for: replying_to, as: keypair.pubkey)
    }

    /// Whether this composer offers the lock at all.
    var can_reply_privately: Bool {
        return private_reply_recipient != nil
    }

    /// Whether the lock is on and cannot be turned off: the note being replied to is itself a private
    /// reply.
    ///
    /// This is the sharpest foot-gun in the feature. The parent is a rumor whose content two people
    /// have; a public reply to it would carry an `e` tag to an id nobody else can resolve and, in
    /// practice, the user paraphrasing what they just read. So it is not a default the user can
    /// change — it is a property of what they are replying to.
    ///
    /// Only the *direct* parent is consulted. A public note under a private ancestor is replied to
    /// publicly, because the note being answered is already public; privacy belongs to a message, not
    /// to a thread. See ``NIP59/privateAudience(for:as:)``, which reads the audience by
    /// the same rule.
    var private_reply_required: Bool {
        guard case .replying_to(let replying_to) = action else { return false }
        return replying_to.is_private_reply
    }

    /// Whether the note about to be sent is a private reply. Distinct from ``is_private_reply``, which
    /// is only the toggle's position: this is the one the send path and the button label ask.
    var sending_privately: Bool {
        return can_reply_privately && (is_private_reply || private_reply_required)
    }

    func send_post() async {
        if voice.mode == .audio {
            guard !sending_privately, !private_reply_required, voice.supportsAction else { return }
            if voice.draft?.phase == .accepted {
                if await voice.finishAccepted() { dismiss() }
            } else {
                await voice.send()
            }
            return
        }
        // Posting text also leaves this sheet; switching formats must not bypass audio discard.
        if voice.needsDiscardConfirmation {
            postTextAfterDiscard = true
            _ = voice.requestDismiss()
            return
        }
        let new_post = await build_post(state: self.damus_state, post: self.post, action: action, uploadedMedias: uploadedMedias, references: self.references, filtered_pubkeys: filtered_pubkeys)

        if sending_privately, case .replying_to(let replying_to) = action {
            notify(.post(.privateReply(new_post, replyingTo: replying_to)))
        } else {
            notify(.post(.post(new_post)))
        }

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
        if voice.dismissalLocked { return true }
        if voice.mode == .audio {
            return sending_privately || private_reply_required || (voice.draft?.phase != .accepted && !voice.canSend)
        }
        // A pubkey-only login can read a private reply but cannot seal one, and there is no public
        // reply for this composer to fall back to. The reply affordance is already absent for that
        // case (``NoteActions/available(on:keypair:)``), so this composer should be unreachable —
        // but `.compose` is a notification anyone can post, and the failure it would otherwise have
        // is the one failure this feature must never have.
        if private_reply_required && !can_reply_privately { return true }

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
            preUploadedMedia.removeAll()
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
    
    var GIFButton: some View {
        Button(action: {
            attach_gif = true
        }, label: {
            Image("GIF")
                .padding(6)
        })
    }
    
    /// The lock, and the audience it decides, split in two: this button holds the *control*, and
    /// ``ReplyView``'s "Replying privately to @a" line holds the *statement*.
    ///
    /// The worst outcome this feature can have is a user believing a note is private when it is
    /// public, and the second worst is the reverse — so the composer has to answer "who can see
    /// this" in words while they are still typing. It just does not have to answer it twice. It used
    /// to: a full-width row here said "Only you and @a can see this reply" directly under a reply
    /// line that was still listing the thread's `p` tags, and the more prominent of the two
    /// statements was the wrong one. Moving the sentence up into the reply line — the place the user
    /// is already reading to find out who they are talking to — leaves exactly one audience
    /// statement, and it is the true one. That is what makes an icon-only control safe here: the
    /// lock never has to carry the meaning on its own.
    ///
    /// When ``private_reply_required`` this is not a control at all: no button, no tap target, drawn
    /// dimmed with the reason carried on its accessibility hint. A toggle that snapped back would
    /// teach the user that the lock is theirs to set and that the app overrode them this once; a
    /// lock that is plainly not a toggle says the truthful thing, which is that this reply's
    /// audience was decided by the note they are answering. The reply line does the explaining.
    @ViewBuilder
    var PrivacyButton: some View {
        if can_reply_privately {
            if private_reply_required {
                privacy_lock
                    .opacity(0.5)
                    .accessibilityIdentifier(AppAccessibilityIdentifiers.post_composer_privacy_toggle.rawValue)
                    .accessibilityLabel(Text("Private reply", comment: "Accessibility label for the lock in the note composer that makes a reply private."))
                    .accessibilityAddTraits(.isSelected)
                    .accessibilityHint(Text("Replies to a private note are always private", comment: "Explanation in the note composer for why a reply cannot be made public."))
            } else {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        is_private_reply.toggle()
                    }
                    post_changed(post: post, media: uploadedMedias)
                }, label: {
                    privacy_lock
                })
                .accessibilityIdentifier(AppAccessibilityIdentifiers.post_composer_privacy_toggle.rawValue)
                .accessibilityLabel(Text("Private reply", comment: "Accessibility label for the lock in the note composer that makes a reply private."))
                .accessibilityAddTraits(sending_privately ? [.isSelected] : [])
            }
        }
    }

    /// The lock itself, sized and padded to sit in the same 24pt box as the image, camera and GIF
    /// icons beside it.
    var privacy_lock: some View {
        Image(systemName: sending_privately ? "lock.fill" : "lock.open")
            .font(.system(size: 21))
            .frame(width: 24, height: 24)
            // The same success palette ``PrivateReplyBadge`` draws the note's own lock in, and
            // deliberately not the purple used elsewhere: the composer is a preview of what the
            // sent note will look like, so the locked state here and the badge there have to read
            // as one thing rather than two features that both involve a lock. Unlocked, it takes the
            // accent tint the image and camera buttons already use — no button style of its own —
            // because an unlocked lock is just another button in the row.
            .foregroundColor(sending_privately ? DamusColors.success : nil)
            .padding(6)
    }

    var AttachmentBar: some View {
        HStack(alignment: .center, spacing: 15) {
            Group {
                ImageButton
                CameraButton
                if damus_state.settings.enable_gifs_feature {
                    GIFButton
                }
            }
            // Only the attachment buttons go dead during an upload. The lock decides where the note
            // is going, which stays the user's to change while an image is still on its way up.
            .disabled(uploading_disabled)
            PrivacyButton
            Spacer()
            AutoSaveIndicatorView(saveViewModel: self.autoSaveModel)
        }
    }
    
    var PostButton: some View {
        // The button label is the last thing a user reads before sending, so it says which of the two
        // things they are about to do. ``PrivacyButton`` is a small icon, and a small icon is easy to
        // mis-tap — so the state it sets is repeated here, in words, on the control that commits it.
        Button(action: {
            Task { await self.send_post() }
        }, label: {
            if voice.mode == .audio {
                Text(voice.draft?.phase == .accepted ? "Done" : (voice.draft?.eventJSON == nil ? "Post" : "Retry Post"))
            } else if sending_privately {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                    Text("Send Privately", comment: "Button to send a reply that is encrypted to its recipient rather than posted publicly.")
                }
            } else {
                Text("Post", comment: "Button to post a note.")
            }
        })
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
        
        let profile = try? damus_state.profiles.lookup(id: pubkey)
        return user_tag_attr_string(profile: profile, pubkey: pubkey)
    }
    
    func clear_draft() {
        switch action {
            case .replying_to(let replying_to):
                damus_state.drafts.replies.removeValue(forKey: replying_to.id)
            case .quoting(let quoting):
                damus_state.drafts.quotes.removeValue(forKey: quoting.id)
            case .posting:
                damus_state.drafts.post = nil
            case .highlighting(let draft):
                damus_state.drafts.highlights.removeValue(forKey: draft)
            case .sharing(_):
                damus_state.drafts.post = nil
        }

        Task{ await damus_state.drafts.save(damus_state: damus_state) }
    }
    
    func load_draft() -> Bool {
        guard let draft = load_draft_for_post(drafts: self.damus_state.drafts, action: self.action) else {
            self.post = NSMutableAttributedString("")
            self.uploadedMedias = []
            self.is_private_reply = false
            self.autoSaveModel.markNothingToSave()   // We should not save empty drafts.
            return false
        }

        self.uploadedMedias = draft.media
        self.post = draft.content
        // A reply the user locked stays locked when they come back to it. Restoring this alongside
        // the text is the whole point of persisting it — the composer reopens saying the same thing
        // about its audience that it said when the user left.
        self.is_private_reply = draft.is_private_reply
        self.autoSaveModel.markSaved()  // The draft we just loaded is saved to memory. Mark it as such.
        return true
    }
    
    /// Use this to signal that the post contents have changed. This will do two things:
    /// 
    /// 1. Save the new contents into our in-memory drafts
    /// 2. Signal that we need to save drafts persistently, which will happen after a certain wait period
    func post_changed(post: NSMutableAttributedString, media: [UploadedMedia]) {
        if let draft = load_draft_for_post(drafts: damus_state.drafts, action: action) {
            draft.content = post
            draft.media = uploadedMedias
            draft.references = references
            draft.filtered_pubkeys = filtered_pubkeys
            draft.is_private_reply = sending_privately
            draft.context_event = action.ev
        } else {
            let artifacts = DraftArtifacts(content: post, media: uploadedMedias, references: references, id: UUID().uuidString, is_private_reply: sending_privately)
            artifacts.context_event = action.ev
            artifacts.filtered_pubkeys = filtered_pubkeys
            set_draft_for_post(drafts: damus_state.drafts, action: action, artifacts: artifacts)
        }
        self.autoSaveModel.needsSaving()
    }
    
    var TextEntry: some View {
        ZStack(alignment: .topLeading) {
            TextViewWrapper(
                attributedText: $post,
                textHeight: $textHeight,
                initialTextSuffix: initial_text_suffix,
                imagePastedFromPasteboard: $imagePastedFromPasteboard,
                imageUploadConfirmPasteboard: $imageUploadConfirmPasteboard,
                cursorIndex: newCursorIndex,
                getFocusWordForMention: { word, range in
                    focusWordAttributes = (word, range)
                    self.newCursorIndex = nil
                },
                updateCursorPosition: { newCursorIndex in
                    self.newCursorIndex = newCursorIndex
                },
                convertMentionRef: { pubkey in
                    let profile = try? damus_state.profiles.lookup(id: pubkey)

                    if profile == nil {
                        fetchProfileAndUpdateMention(pubkey: pubkey)
                    }

                    return user_tag_attr_string(profile: profile, pubkey: pubkey)
                }
            )
                .environmentObject(tagModel)
                .focused($focus)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier(AppAccessibilityIdentifiers.post_composer_text_view.rawValue)
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
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                Button(action: cancel) {
                    Text(voice.draft?.eventJSON == nil ? "Cancel" : "Close", comment: "Close the composer; confirm discarding unpublished audio.").padding(10)
                }
                .buttonStyle(NeutralButtonStyle())
                .accessibilityIdentifier(AppAccessibilityIdentifiers.post_composer_cancel_button.rawValue)
                .disabled(voice.dismissalLocked)
                if let error { Text(error).foregroundColor(.red) }
                Spacer()
                PostButton
            }
            if voice.supportsAction && !sending_privately && !private_reply_required {
                Picker("Post format", selection: Binding(get: { voice.mode }, set: { value in
                    voice.changeMode(value)
                    focusWordAttributes = (nil, nil)
                    // Keep keyboard focus local to the composer, including in app extensions.
                    focus = value == .text
                })) {
                    Text("Text").tag(VoiceComposerModel.Mode.text)
                    Text("Audio").tag(VoiceComposerModel.Mode.audio)
                }
                .pickerStyle(.segmented)
                .disabled(voice.dismissalLocked)
                .accessibilityIdentifier("post.format")
            }
            Divider().foregroundColor(DamusColors.neutral3)
        }
        .padding(.horizontal)
        .padding(.top, 15)
    }

    @discardableResult
    func handle_upload(media: MediaUpload) async -> Bool {
        mediaUploadUnderProgress = media
        let uploader = damus_state.settings.default_media_uploader
        
        let img = getImage(media: media)
        print("img size w:\(img.size.width) h:\(img.size.height)")
        
        async let blurhash = calculate_blurhash(img: img)
        let res = await image_upload.start(media: media, uploader: uploader, mediaType: .normal, keypair: damus_state.keypair)
        
        mediaUploadUnderProgress = nil
        switch res {
        case .success(let url):
            guard let url = URL(string: url) else {
                self.error = "Error uploading image :("
                return false
            }
            let blurhash = await blurhash
            let meta = blurhash.map { bh in calculate_image_metadata(url: url, img: img, blurhash: bh) }
            let uploadedMedia = UploadedMedia(localURL: media.localURL, uploadedURL: url, metadata: meta)
            uploadedMedias.append(uploadedMedia)
            return true
            
        case .failed(let error):
            if let error {
                self.error = error.localizedDescription
            } else {
                self.error = "Error uploading image :("
            }
            return false
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
    
    /// Audio reviews span the sheet; text keeps its existing avatar-and-editor layout.
    func Editor(deviceSize: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if voice.mode == .audio {
                        VStack(alignment: .leading, spacing: 12) {
                            if let prompt_view { prompt_view() }
                            VoiceTranscriptReview(model: voice)
                        }
                    } else {
                        HStack(alignment: .top) {
                            ProfilePicView(pubkey: damus_state.pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation, damusState: damus_state)
                            VStack(alignment: .leading) {
                                if let prompt_view { prompt_view() }
                                TextEntry
                            }
                        }
                    }
                }
                .id("post")
                
                if voice.mode == .text {
                    PVImageCarouselView(media: $uploadedMedias,
                                        mediaUnderProgress: $mediaUploadUnderProgress,
                                        imageUploadModel: image_upload,
                                        deviceWidth: deviceSize.size.width)
                        .onChange(of: uploadedMedias) { media in
                            post_changed(post: post, media: media)
                        }
                }
                
                if case .quoting(let ev) = action {
                    BuilderEventView(damus: damus_state, event: ev)
                }
                else if case .highlighting(let draft) = action {
                    HighlightDraftContentView(draft: draft)
                }
                else if case .sharing(let draft) = action,
                        let url = draft.getLinkURL() {
                    LinkViewRepresentable(meta: .url(url))
                        .frame(height: 50)
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
                let searching = voice.mode == .text ? get_searching_string(focusWordAttributes.0) : nil
                let searchingHashTag = voice.mode == .text ? get_searching_hashTag(focusWordAttributes.0) : nil
                TopBar
                
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(alignment: .leading) {
                            if case .replying_to(let replying_to) = self.action {
                                ReplyView(replying_to: replying_to,
                                          damus: damus_state,
                                          original_pubkeys: pubkeys,
                                          filtered_pubkeys: $filtered_pubkeys,
                                          sending_privately: sending_privately,
                                          private_reply_recipient: private_reply_recipient)
                            }
                            
                            Editor(deviceSize: deviceSize)
                                .padding(.top, 5)
                        }
                    }
                    .frame(maxHeight: searching == nil && searchingHashTag == nil ? deviceSize.size.height : 70)
                    .onAppear {
                        scroll_to_event(scroller: scroller, id: "post", delay: 1.0, animate: true, anchor: .top)
                    }
                }
                
                // This if-block observes @ for tagging
                if voice.mode == .audio {
                    VoiceRecordingBar(model: voice)
                } else if let searching {
                    UserSearch(damus_state: damus_state, search: searching, focusWordAttributes: $focusWordAttributes, newCursorIndex: $newCursorIndex, post: $post)
                        .frame(maxHeight: .infinity)
                        .environmentObject(tagModel)
                // This else observes '#' for hash-tag suggestions and creates SuggestedHashtagsView
                } else if let searchingHashTag {
                        SuggestedHashtagsView(damus_state: damus_state,
                                              events: SearchHomeModel(damus_state: damus_state).events,
                                              isFromPostView: true,
                                              queryHashTag: searchingHashTag,
                                              focusWordAttributes: $focusWordAttributes,
                                              newCursorIndex: $newCursorIndex,
                                              post: $post)
                        .environmentObject(tagModel)
               } else {
                    Divider()
                    AttachmentBar
                        .padding(.vertical, 5)
                        .padding(.horizontal)
                }
            }
            .background(DamusColors.adaptableWhite.edgesIgnoringSafeArea(.all))
            .background(VoiceComposerDismissGuard(blocked: voice.needsDiscardConfirmation || voice.dismissalLocked, onAttempt: cancel))
            .alert("Are you sure you want to discard this audio post before posting it?", isPresented: $voice.confirmingDiscard) {
                Button("Yes, discard", role: .destructive) {
                    Task {
                        guard await voice.discardAndClose() else { return }
                        if postTextAfterDiscard {
                            postTextAfterDiscard = false
                            await send_post()
                        } else { finishCancel() }
                    }
                }
                Button("Keep editing", role: .cancel) {
                    postTextAfterDiscard = false
                    voice.keepEditing()
                }
            }
            .sheet(isPresented: $attach_media) {
                MediaPicker(mediaPickerEntry: .postView, onMediaSelected: { image_upload_confirm = true }) { media in
                    self.preUploadedMedia.append(media)
                }
                .alert(NSLocalizedString("Are you sure you want to upload the selected media?", comment: "Alert message asking if the user wants to upload media."), isPresented: $image_upload_confirm) {
                    Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                        // initiate asynchronous uploading Task for multiple-images
                        let task = Task {
                            for media in preUploadedMedia {
                                if let mediaToUpload = generateMediaUpload(media) {
                                    await self.handle_upload(media: mediaToUpload)
                                }
                            }
                        }
                        uploadTasks.append(task)
                        self.attach_media = false
                    }
                    Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {
                        preUploadedMedia.removeAll()
                    }
                }
            }
            .sheet(isPresented: $attach_camera) {
                CameraController(uploader: damus_state.settings.default_media_uploader, mode: .save_to_library(when_done: {
                    self.attach_camera = false
                    self.attach_media = true
                }))
            }
            .sheet(isPresented: $attach_gif) {
                GIFPickerView(damus_state: damus_state) { gifURL in
                    let uploadedMedia = UploadedMedia(localURL: gifURL, uploadedURL: gifURL, metadata: nil)
                    uploadedMedias.append(uploadedMedia)
                    post_changed(post: post, media: uploadedMedias)
                    attach_gif = false
                }
            }
            // This alert seeks confirmation about Image-upload when user taps Paste option
            .alert(NSLocalizedString("Are you sure you want to upload this media?", comment: "Alert message asking if the user wants to upload media."), isPresented: $imageUploadConfirmPasteboard) {
                Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                    if let image = imagePastedFromPasteboard,
                       let mediaToUpload = generateMediaUpload(image) {
                        let task = Task {
                            _ = await self.handle_upload(media: mediaToUpload)
                        }
                        uploadTasks.append(task)
                    }
                }
                Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
            }
            // This alert seeks confirmation about media-upload from Damus Share Extension
            .alert(NSLocalizedString("Are you sure you want to upload the selected media?", comment: "Alert message asking if the user wants to upload media."), isPresented: $imageUploadConfirmDamusShare) {
                Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                    let task = Task {
                        for media in preUploadedMedia {
                            if let mediaToUpload = generateMediaUpload(media) {
                                await self.handle_upload(media: mediaToUpload)
                            }
                        }
                    }
                    uploadTasks.append(task)
                }
                Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
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
                    case .sharing(let content):
                        if let url = content.getLinkURL() {
                            self.post = NSMutableAttributedString(string: "\(content.title)\n\(String(url.absoluteString))")
                        } else {
                            self.preUploadedMedia = content.getMediaArray()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.imageUploadConfirmDamusShare = true // display Confirm Sheet after 1 sec
                            }
                        }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.focus = voice.mode == .text
                }
            }
            .onChange(of: sending_privately) { isPrivate in
                if isPrivate { voice.changeMode(.text) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                voice.suspend()
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                if let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   AVAudioSession.InterruptionType(rawValue: raw) == .began { voice.suspend() }
            }
            .onDisappear {
                voice.disappear()
                if isEmpty() {
                    clear_draft()
                }
                preUploadedMedia.removeAll()
                cancelProfileFetchTasks()
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

fileprivate func get_searching_hashTag(_ word: String?) -> String? {
    guard let word,
          word.count >= 2,
          let first_char = word.first,
          first_char == "#" else {
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
    @Binding var mediaUnderProgress: MediaUpload?
    @ObservedObject var imageUploadModel: ImageUploadModel

    let deviceWidth: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(media.indices, id: \.self) { index in
                    if isSupportedVideo(url: media[index].uploadedURL) {
                        VideoPlayer(player: configurePlayer(with: media[index].localURL))
                            .aspectRatio(contentMode: .fit)
                            .frame(width: media.count == 1 ? deviceWidth * 0.8 : 250, alignment: .topLeading)
                            .cornerRadius(10)
                            .contextMenu { contextMenuContent(for: media[index]) }
                            .overlay(
                                Button(action: {
                                    media.remove(at: index)
                                }) {
                                    closeImageView
                                }
                                    .padding([.top, .leading], 8),
                                alignment: .topLeading
                            )
                            .overlay(
                                Image(systemName: "video")
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                    .shadow(radius: 5)
                                    .opacity(0.6),
                                alignment: .bottomLeading
                            )
                    } else {
                        KFAnimatedImage(media[index].uploadedURL)
                            .imageContext(.note, disable_animation: false)
                            .configure { view in
                                view.framePreloadCount = 3
                            }
                            .aspectRatio(contentMode: .fit)
                            .frame(width: media.count == 1 ? deviceWidth * 0.8 : 250, alignment: .topLeading)
                            .cornerRadius(10)
                            .contextMenu { contextMenuContent(for: media[index]) }
                            .overlay(
                                Button(action: {
                                    media.remove(at: index)
                                }) {
                                    closeImageView
                                }
                                    .padding([.top, .leading], 8),
                                alignment: .topLeading
                            )
                    }
                }
                if let mediaUP = mediaUnderProgress, let progress = imageUploadModel.progress {
                    ZStack {
                        // Media under upload-progress
                        Image(uiImage: getImage(media: mediaUP))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: media.count == 1 ? deviceWidth * 0.8 : 250, alignment: .topLeading)
                            .cornerRadius(10)
                            .opacity(0.3)
                            .padding()
                        // Circle showing progress on top of media
                        Circle()
                            .trim(from: 0, to: CGFloat(progress))
                            .stroke(Color.damusPurple, lineWidth: 5.0)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 30, height: 30)
                            .padding()
                    }
                }
            }
            .padding()
        }
    }
    
    // Helper Function for Context Menu
    @ViewBuilder
    private func contextMenuContent(for mediaItem: UploadedMedia) -> some View {
        Button(action: {
            UIPasteboard.general.string = mediaItem.uploadedURL.absoluteString
        }) {
            Label(
                NSLocalizedString("Copy URL", comment: "Copy URL of the selected uploaded media asset."),
                systemImage: "doc.on.doc"
            )
        }
    }
    
    private func configurePlayer(with url: URL) -> AVPlayer {
        let player = AVPlayer(url: url)
        player.allowsExternalPlayback = false
        player.usesExternalPlaybackWhileExternalScreenIsActive = false
        return player
    }

    private var closeImageView: some View {
        Image("close-circle")
            .foregroundColor(.white)
            .background(Color.black.opacity(0.5))
            .clipShape(Circle())
            .shadow(radius: 5)
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
    let metadata: ImageMetadata?
}


func set_draft_for_post(drafts: Drafts, action: PostAction, artifacts: DraftArtifacts) {
    switch action {
    case .replying_to(let ev):
        drafts.replies[ev.id] = artifacts
    case .quoting(let ev):
        drafts.quotes[ev.id] = artifacts
    case .posting:
        drafts.post = artifacts
    case .highlighting(let draft):
        drafts.highlights[draft] = artifacts
    case .sharing(_):
        drafts.post = artifacts
    }
}

func load_draft_for_post(drafts: Drafts, action: PostAction) -> DraftArtifacts? {
    switch action {
    case .replying_to(let ev):
        return drafts.replies[ev.id]
    case .quoting(let ev):
        return drafts.quotes[ev.id]
    case .posting:
        return drafts.post
    case .highlighting(let highlight):
        if let exact_match = drafts.highlights[highlight] {
            return exact_match  // Always prefer to return the draft for that exact same highlight
        }
        // If there are no exact matches to the highlight, try to load a draft for the same highlight source
        // We do this to improve UX, because we don't want to leave the post view blank if they only selected a slightly different piece of text from before.
        let other_matches = drafts.highlights
            .filter { $0.key.source == highlight.source }
        // It's not an exact match, so there is no way of telling which one is the preferred draft. So just load the first one we found.
        return other_matches.first?.value
    case .sharing(_):
        return drafts.post
    }
}

private func isAlphanumeric(_ char: Character) -> Bool {
    return char.isLetter || char.isNumber
}

/// Generates NIP-10 compliant e-tags for replies.
/// Format: `["e", <event-id>, <relay-url>, <marker>, <pubkey>]`
func nip10_reply_tags(replying_to: NostrEvent, keypair: Keypair, relayURL: RelayURL?) -> [[String]] {
    if replying_to.known_kind == .voice {
        return VoiceEventBuilder.replyTags(parent: replying_to, relay: relayURL?.absoluteString ?? "")
    }
    guard let nip10 = replying_to.thread_reply() else {
        // we're replying to a post that isn't in a thread,
        // just add a single reply-to-root tag
        return [["e", replying_to.id.hex(), relayURL?.absoluteString ?? "", "root", replying_to.pubkey.hex()]]
    }

    // otherwise use the root tag from the parent's nip10 reply and include the note
    // that we are replying to's note id.
    var rootTag = ["e", nip10.root.note_id.hex(), nip10.root.relay ?? "", "root"]
    if let rootPubkey = nip10.root.pubkey {
        rootTag.append(rootPubkey.hex())
    }

    let replyTag = ["e", replying_to.id.hex(), relayURL?.absoluteString ?? "", "reply", replying_to.pubkey.hex()]

    return [rootTag, replyTag]
}

func build_post(state: DamusState, action: PostAction, draft: DraftArtifacts) async -> NostrPost {
    return await build_post(
        state: state,
        post: draft.content,
        action: action,
        uploadedMedias: draft.media,
        references: draft.references,
        filtered_pubkeys: draft.filtered_pubkeys
    )
}

func build_post(state: DamusState, post: NSAttributedString, action: PostAction, uploadedMedias: [UploadedMedia], references: [RefId], filtered_pubkeys: Set<Pubkey>) async -> NostrPost {
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
    
    return await build_post(state: state, post: post, action: action, uploadedMedias: uploadedMedias, pubkeys: pks)
}

/// This builds a Nostr post from draft data from `PostView` or other draft-related classes
///
/// ## Implementation notes
///
/// - This function _likely_ causes no side-effects, and _should not_ cause side-effects to any of the inputs.
///
/// - Parameters:
///   - state: The damus state, needed to fetch more Nostr data to form this event
///   - post: The text content from `PostView`.
///   - action: The intended action of the post (highlighting? replying?)
///   - uploadedMedias: The medias attached to this post
///   - pubkeys: The referenced pubkeys
/// - Returns: A NostrPost, which can then be signed into an event.
func build_post(state: DamusState, post: NSAttributedString, action: PostAction, uploadedMedias: [UploadedMedia], pubkeys: [Pubkey]) async -> NostrPost {
    let post = NSMutableAttributedString(attributedString: post)
    post.enumerateAttributes(in: NSRange(location: 0, length: post.length), options: []) { attributes, range, stop in
        let linkValue = attributes[.link]
        let link = (linkValue as? String) ?? (linkValue as? URL)?.absoluteString
        if let link {
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
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let imagesString = uploadedMedias.map { $0.uploadedURL.absoluteString }.joined(separator: "\n")

    if !imagesString.isEmpty {
        content.append("\n\n" + imagesString)
    }

    var tags: [[String]] = []

    switch action {
    case .replying_to(let replying_to):
        // start off with the reply tags
        tags = nip10_reply_tags(replying_to: replying_to, keypair: state.keypair, relayURL: await state.nostrNetwork.relaysForEvent(event: replying_to).first)

    case .quoting(let ev):
        let relay_urls = await state.nostrNetwork.relaysForEvent(event: ev)
        let nevent = Bech32Object.encode(.nevent(NEvent(event: ev, relays: relay_urls.prefix(4).map { $0 })))
        content.append("\n\nnostr:\(nevent)")

        if let first_relay = relay_urls.first?.absoluteString {
            tags.append(["q", ev.id.hex(), first_relay, ev.pubkey.hex()]);
            tags.append(["p", ev.pubkey.hex(), first_relay])
        } else {
            tags.append(["q", ev.id.hex(), "", ev.pubkey.hex()]);
            tags.append(["p", ev.pubkey.hex()])
        }
    case .posting, .highlighting, .sharing:
        break
    }

    // append additional tags
    tags += uploadedMedias.compactMap { $0.metadata?.to_tag() }
    
    switch action {
        case .highlighting(let draft):
            tags.append(contentsOf: draft.source.tags())
            if !(content.isEmpty || content.allSatisfy { $0.isWhitespace })  {
                tags.append(["comment", content])
            }
            tags += pubkeys.map { pk in
                ["p", pk.hex(), "mention"]
            }
            return NostrPost(content: draft.selected_text, kind: .highlight, tags: tags)
        default:
            tags += pubkeys.map { pk in
                ["p", pk.hex()]
            }
    }

    return NostrPost(content: content.trimmingCharacters(in: .whitespacesAndNewlines), kind: .text, tags: tags)
}

func isSupportedVideo(url: URL?) -> Bool {
    guard let url = url else { return false }
    let fileExtension = url.pathExtension.lowercased()
    let supportedUTIs = AVURLAsset.audiovisualTypes().map { $0.rawValue }
    return supportedUTIs.contains { utiString in
        if let utType = UTType(utiString), let fileUTType = UTType(filenameExtension: fileExtension) {
            return fileUTType.conforms(to: utType)
        }
        return false
    }
}

func isSupportedImage(url: URL) -> Bool {
    let fileExtension = url.pathExtension.lowercased()
    // It would be better to pull this programmatically from Apple's APIs, but there seems to be no such call
    let supportedTypes = ["jpg", "png", "gif"]
    return supportedTypes.contains(fileExtension)
}

