//
//  DraftsModel.swift
//  damus
//
//  Created by Terry Yiu on 2/12/23.
//

import Foundation
import SwiftUICore
import UIKit

/// Represents artifacts in a post draft, which is rendered by `PostView`
///
/// ## Implementation notes
///
/// - This is NOT `Codable` because we store these persistently as NIP-37 drafts in NostrDB, instead of directly encoding the object.
///     - `NSMutableAttributedString` is the bottleneck for making this `Codable`, and replacing that with another type requires a very large refactor.
/// - Encoding/decoding logic is lossy, and is not fully round-trippable. This class does a best effort attempt at encoding and recovering as much information as possible, but the information is dispersed into many different places, types, and functions around the code, making round-trip guarantees very difficult without severely refactoring `PostView`, `TextViewWrapper`, and other associated classes, unfortunately. These are the known limitations at the moment:
///     - Image metadata is lost on decoding
///     - The `filtered_pubkeys` filter effectively gets applied upon encoding, causing them to change upon decoding
///
class DraftArtifacts: Equatable {
    /// The text content of the note draft
    ///
    /// ## Implementation notes
    ///
    /// - This serves as the backing model for `PostView` and `TextViewWrapper`. It might be cleaner to use a specialized data model for this in the future and render to attributed string in real time, but that will require a big refactor. See https://github.com/damus-io/damus/issues/1862#issuecomment-2585756932
    var content: NSMutableAttributedString
    /// A list of media items that have been attached to the note draft.
    var media: [UploadedMedia]
    /// The references for this note, which will be translated into tags once the event is published.
    var references: [RefId]
    /// Pubkeys that should be filtered out from the references
    ///
    /// For example, when replying to an event, the user can select which pubkey mentions they want to keep, and which ones to remove.
    var filtered_pubkeys: Set<Pubkey> = []
    
    /// A unique ID for this draft that allows us to address these if we need to.
    ///
    /// This will be the unique identifier in the NIP-37 note
    let id: String
    
    init(content: NSMutableAttributedString = NSMutableAttributedString(string: ""), media: [UploadedMedia] = [], references: [RefId], id: String) {
        self.content = content
        self.media = media
        self.references = references
        self.id = id
    }
    
    static func == (lhs: DraftArtifacts, rhs: DraftArtifacts) -> Bool {
        return (
            lhs.media == rhs.media &&
            lhs.content.string == rhs.content.string    // Comparing the text content is not perfect but acceptable in this case because attributes for our post editor are determined purely from text content
        )
    }
    
    
    // MARK: Encoding and decoding functions to and from NIP-37 nostr events
    
    /// Converts the draft artifacts into a NIP-37 draft event that can be saved into NostrDB or any Nostr relay
    /// 
    /// - Parameters:
    ///   - action: The post action for this draft, which provides necessary context for the draft (e.g. Is it meant to highlight something? Reply to something?)
    ///   - damus_state: The damus state, needed for encrypting, fetching Nostr data depedencies, and forming the NIP-37 draft
    ///   - references: references in the post?
    /// - Returns: The NIP-37 draft packaged in a way that can be easily wrapped/unwrapped.
    func to_nip37_draft(action: PostAction, damus_state: DamusState) throws -> NIP37Draft? {
        guard let keypair = damus_state.keypair.to_full() else { return nil }
        let post = build_post(state: damus_state, action: action, draft: self)
        guard let note = post.to_event(keypair: keypair) else { return nil }
        return try NIP37Draft(unwrapped_note: note, draft_id: self.id, keypair: keypair)
    }
    
    /// Instantiates a draft object from a NIP-37 draft
    /// - Parameters:
    ///   - nip37_draft: The NIP-37 draft object
    ///   - damus_state: Damus state of the user who wants to load this draft object. Needed for pulling profiles from Ndb, and decrypting contents.
    /// - Returns: A draft artifacts object, or `nil` if such cannot be loaded.
    static func from(nip37_draft: NIP37Draft, damus_state: DamusState) -> DraftArtifacts? {
        return Self.from(
            event: nip37_draft.unwrapped_note,
            draft_id: nip37_draft.id ?? UUID().uuidString,  // Generate random UUID as the draft ID if none is specified. It is always better to have an ID that we can use for addressing later.
            damus_state: damus_state
        )
    }
    
    /// Load a draft artifacts object from a plain, unwrapped NostrEvent
    ///
    /// This function will parse the contents of a Nostr Event and turn it into an editable draft that we can use.
    ///
    /// - Parameters:
    ///   - event: The Nostr event to use as a template
    ///   - draft_id: The unique ID of this draft, used for keeping draft identities stable. UUIDs are recommended but not required.
    ///   - damus_state: The user's Damus state, used for fetching profiles in NostrDB
    /// - Returns: The draft that can be loaded into `PostView`.
    static func from(event: NostrEvent, draft_id: String, damus_state: DamusState) -> DraftArtifacts? {
        guard let parsed_blocks = parse_note_content(content: .init(note: event, keypair: damus_state.keypair)) else {
            return nil
        }
        return Self.from(parsed_blocks: parsed_blocks, references: Array(event.references), draft_id: draft_id, damus_state: damus_state)
    }
    
    /// Load a draft artifacts object from parsed Nostr event blocks
    /// 
    /// - Parameters:
    ///   - parsed_blocks: The blocks parsed from a Nostr event
    ///   - references: The references in the Nostr event
    ///   - draft_id: The unique ID of the draft as per NIP-37
    ///   - damus_state: Damus state, used for fetching profile info in NostrDB
    /// - Returns: The draft that can be loaded into `PostView`.
    static func from(parsed_blocks: Blocks, references: [RefId], draft_id: String, damus_state: DamusState) -> DraftArtifacts {
        let rich_text_content: NSMutableAttributedString = .init(string: "")
        var media: [UploadedMedia] = []
        for block in parsed_blocks.blocks {
            switch block {
            case .mention(let mention):
                if let pubkey = mention.ref.nip19.pubkey() {
                    // A profile reference, format things properly.
                    let profile = damus_state.ndb.lookup_profile(pubkey)?.unsafeUnownedValue?.profile
                    let profile_name = DisplayName(profile: profile, pubkey: pubkey).username
                    guard let url_address = URL(string: block.asString) else {
                        rich_text_content.append(.init(string: block.asString))
                        continue
                    }
                    let attributed_string = NSMutableAttributedString(
                        string: "@\(profile_name)",
                        attributes: [
                            .link: url_address,
                            .foregroundColor: UIColor(Color.accentColor)
                        ]
                    )
                    rich_text_content.append(attributed_string)
                } else if case .note(_) = mention.ref.nip19 {
                    // These note references occur when we quote a note, and since that is tracked via `PostAction` in `PostView`, ignore it here to avoid attaching the same event twice in a note
                    continue
                } else {
                    // Other references
                    rich_text_content.append(.init(string: block.asString))
                }
            case .url(let url):
                if isSupportedImage(url: url) {
                    // Image, add that to our media attachments
                    // TODO: Add metadata decoding support
                    media.append(UploadedMedia(localURL: url, uploadedURL: url, metadata: .none))
                    continue
                }
                else {
                    // Normal URL, plain text
                    rich_text_content.append(.init(string: block.asString))
                }
            case .invoice(_), .relay(_), .hashtag(_), .text(_):
                // Everything else is currently plain text.
                rich_text_content.append(.init(string: block.asString))
            }
        }
        return DraftArtifacts(content: rich_text_content, media: media, references: references, id: draft_id)
    }
}


/// Holds and keeps track of the note post drafts throughout the app.
class Drafts: ObservableObject {
    @Published var post: DraftArtifacts? = nil
    @Published var replies: [NoteId: DraftArtifacts] = [:]
    @Published var quotes: [NoteId: DraftArtifacts] = [:]
    /// The drafts we have for highlights
    ///
    /// ## Implementation notes
    /// - Although in practice we also load drafts based on the highlight source for better UX (making it easier to find a draft), we need the keys to be of type `HighlightContentDraft` because we need the selected text information to be able to construct the NIP-37 draft, as well as to load that into post view.
    @Published var highlights: [HighlightContentDraft: DraftArtifacts] = [:]
    
    /// Loads drafts from storage (NostrDB + UserDefaults)
    func load(from damus_state: DamusState) {
        guard let note_ids = damus_state.settings.draft_event_ids?.compactMap({ NoteId(hex: $0) }) else { return }
        for note_id in note_ids {
            let txn = damus_state.ndb.lookup_note(note_id)
            guard let note = txn?.unsafeUnownedValue else { continue }
            // Implementation note: This currently fails silently, because:
            // 1. Errors are unlikely and not expected
            // 2. It is not mission critical to recover from this error
            // 3. The changes that add a error view sheet with useful info is not yet merged in as of writing.
            try? self.load(wrapped_draft_note: note, with: damus_state)
        }
    }
    
    /// Loads a specific NIP-37 note into this class
    func load(wrapped_draft_note: NdbNote, with damus_state: DamusState) throws {
        // Extract draft info from the NIP-37 note
        guard let full_keypair = damus_state.keypair.to_full() else { return }
        guard let nip37_draft = try NIP37Draft(wrapped_note: wrapped_draft_note, keypair: full_keypair) else { return }
        guard let known_kind = nip37_draft.unwrapped_note.known_kind else { return }
        guard let draft_artifacts = DraftArtifacts.from(
            nip37_draft: nip37_draft,
            damus_state: damus_state
        ) else { return }
        
        // Find out where to place these drafts
        guard let blocks = parse_note_content(content: .note(nip37_draft.unwrapped_note)) else {
            return
        }

        switch known_kind {
        case .text:
            if let replied_to_note_id = nip37_draft.unwrapped_note.direct_replies() {
                self.replies[replied_to_note_id] = draft_artifacts
            }
            else {
                for block in blocks.blocks {
                    if case .mention(let mention) = block {
                        if case .note(let note_id) = mention.ref.nip19 {
                            self.quotes[note_id] = draft_artifacts
                            return
                        }
                    }
                }
                self.post = draft_artifacts
            }
        case .highlight:
            guard let highlight = HighlightContentDraft(from: nip37_draft.unwrapped_note) else { return }
            self.highlights[highlight] = draft_artifacts
        default:
            return
        }
    }
    
    /// Saves the drafts tracked by this class persistently using NostrDB + UserDefaults
    func save(damus_state: DamusState) {
        var draft_events: [NdbNote] = []
        post_artifact_block: if let post_artifacts = self.post {
            let nip37_draft = try? post_artifacts.to_nip37_draft(action: .posting(.user(damus_state.pubkey)), damus_state: damus_state)
            guard let wrapped_note = nip37_draft?.wrapped_note else { break post_artifact_block }
            draft_events.append(wrapped_note)
        }
        for (replied_to_note_id, reply_artifacts) in self.replies {
            guard let replied_to_note = damus_state.ndb.lookup_note(replied_to_note_id)?.unsafeUnownedValue?.to_owned() else { continue }
            let nip37_draft = try? reply_artifacts.to_nip37_draft(action: .replying_to(replied_to_note), damus_state: damus_state)
            guard let wrapped_note = nip37_draft?.wrapped_note else { continue }
            draft_events.append(wrapped_note)
        }
        for (quoted_note_id, quote_note_artifacts) in self.quotes {
            guard let quoted_note = damus_state.ndb.lookup_note(quoted_note_id)?.unsafeUnownedValue?.to_owned() else { continue }
            let nip37_draft = try? quote_note_artifacts.to_nip37_draft(action: .quoting(quoted_note), damus_state: damus_state)
            guard let wrapped_note = nip37_draft?.wrapped_note else { continue }
            draft_events.append(wrapped_note)
        }
        for (highlight, highlight_note_artifacts) in self.highlights {
            let nip37_draft = try? highlight_note_artifacts.to_nip37_draft(action: .highlighting(highlight), damus_state: damus_state)
            guard let wrapped_note = nip37_draft?.wrapped_note else { continue }
            draft_events.append(wrapped_note)
        }
        
        for draft_event in draft_events {
            // Implementation note: We do not support draft synchronization with relays yet.
            // TODO: Once it is time to implement draft syncing with relays, please consider the following:
            // - Privacy: Sending drafts to the network leaks metadata about app activity, and may break user expectations
            // - Down-sync conflict resolution: Consider how to solve conflicts for different draft versions holding the same ID (e.g. edited in Damus, then another client, then Damus again)
            damus_state.nostrNetwork.pool.send_raw_to_local_ndb(.typical(.event(draft_event)))
        }
        
        damus_state.settings.draft_event_ids = draft_events.map({ $0.id.hex() })
    }
}

// MARK: - Convenience extensions

fileprivate extension Array {
    mutating func appendIfNotNil(_ element: Element?) {
        if let element = element {
            self.append(element)
        }
    }
}
