//
//  DraftsModel.swift
//  damus
//
//  Created by Terry Yiu on 2/12/23.
//

import Foundation
import SwiftUI
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
    /// Whether the composer had the lock on when this draft was last touched — that is, whether this
    /// is a draft of a **private reply**.
    ///
    /// A draft that came back without this would come back as a *public* reply, which is the one
    /// failure this feature must never have. It is stored, not merely held in memory, so it survives
    /// the app being killed with the composer open; see ``NIP37Draft/is_private_reply``.
    ///
    /// Only meaningful for a reply draft. Nothing else in the app can be private, and `PostView`
    /// ignores it outside `.replying_to`, so a draft that somehow carries it elsewhere is inert
    /// rather than wrong.
    var is_private_reply: Bool = false

    /// A unique ID for this draft that allows us to address these if we need to.
    ///
    /// This will be the unique identifier in the NIP-37 note
    let id: String

    /// Keep the captured parent while editing, and its authored tags after a restart.
    var context_event: NostrEvent?
    private var restored_event: NostrEvent?

    init(content: NSMutableAttributedString = NSMutableAttributedString(string: ""), media: [UploadedMedia] = [], references: [RefId], id: String, is_private_reply: Bool = false) {
        self.content = content
        self.media = media
        self.references = references
        self.id = id
        self.is_private_reply = is_private_reply
    }
    
    static func == (lhs: DraftArtifacts, rhs: DraftArtifacts) -> Bool {
        return (
            lhs.media == rhs.media &&
            lhs.is_private_reply == rhs.is_private_reply &&     // Flipping the lock changes the draft even when not a character of it changed
            lhs.content.string == rhs.content.string    // Comparing the text content is not perfect but acceptable in this case because attributes for our post editor are determined purely from text content
        )
    }
    
    
    // MARK: Encoding and decoding functions to and from NIP-37 nostr events
    
    /// Converts the draft artifacts into a NIP-37 draft that can be saved into NostrDB
    ///
    /// - Parameters:
    ///   - action: The post action for this draft, which provides necessary context for the draft (e.g. Is it meant to highlight something? Reply to something?)
    ///   - damus_state: The damus state, needed for signing, fetching Nostr data depedencies, and forming the NIP-37 draft
    /// - Returns: The NIP-37 draft packaged in a way that can be easily wrapped/unwrapped.
    ///
    /// ## Implementation notes
    ///
    /// - The drafted note itself is still built and **signed** by the ordinary posting path
    ///   (`build_post` -> `to_event`), because that path is what makes a draft round-trip into
    ///   something postable, and because the draft event stores it as event JSON — which
    ///   ``NdbNote/owned_from_json(json:bufsize:)`` will not parse back without an `id` and a `sig`.
    ///   The kind-31234 draft event around it is the layer that is left unsigned.
    func to_nip37_draft(action: PostAction, damus_state: DamusState) async throws -> NIP37Draft? {
        guard let keypair = damus_state.keypair.to_full() else { return nil }
        let post = await build_post(state: damus_state, action: action, draft: self)
        guard let note = post.to_event(keypair: keypair, clientTag: damus_state.clientTagComponents) else { return nil }
        // The drafted note is the *public* rendering even for a private reply, and deliberately: a
        // private reply's rumor is byte-identical to the public reply it could have been, so there is
        // one note to store and a flag on the wrapper saying how to reopen it. It is signed here for
        // the same reason every draft is — `owned_from_json` will not read a note back without an
        // `id` and a `sig` — and it is a signature on a note that lives only in the content string of
        // a local, PNS-encrypted draft event, never in nostrdb's note index and never on a relay.
        restored_event = note
        return NIP37Draft(unwrapped_note: note, draft_id: self.id, is_private_reply: self.is_private_reply)
    }
    
    static func quotedNoteID(_ reference: Bech32Object) -> NoteId? {
        switch reference {
        case .note(let id): return id
        case .nevent(let event): return event.noteid
        default: return nil
        }
    }

    static func quoteID(in event: NostrEvent) -> NoteId? {
        guard event.direct_replies() == nil else { return nil }
        return event.tags.strings().lazy.compactMap { tag -> NoteId? in
            guard tag.first == "q", tag.count > 1 else { return nil }
            return NoteId(hex: tag[1])
        }.first
    }

    /// Saving must not depend on the reply/quote target remaining in the database cache.
    func to_nip37_draft(target: NoteId, is_quote: Bool, damus_state: DamusState) async throws -> NIP37Draft? {
        if let parent = context_event?.id == target ? context_event : (try? damus_state.ndb.lookup_note_and_copy(target)) {
            return try await to_nip37_draft(action: is_quote ? .quoting(parent) : .replying_to(parent), damus_state: damus_state)
        }
        guard let template = restored_event, let keypair = damus_state.keypair.to_full(),
              is_quote ? Self.quoteID(in: template) == target : template.direct_replies() == target else { return nil }
        let body = await build_post(state: damus_state, action: .posting(.user(damus_state.pubkey)), draft: self)
        var content = body.content
        let context_tags = template.tags.strings().filter { $0.first == (is_quote ? "q" : "e") }
        if is_quote {
            let blocks = parse_post_blocks(content: template.content)?.blocks ?? []
            let reference = blocks.last { block in
                guard case .mention(let mention) = block else { return false }
                return Self.quotedNoteID(mention.ref.nip19) == target
            }?.asString ?? "nostr:\(bech32_note_id(target))"
            content += "\n\n" + reference
        }
        let post = NostrPost(content: content, kind: .text, tags: context_tags + body.tags)
        guard let note = post.to_event(keypair: keypair, clientTag: damus_state.clientTagComponents) else { return nil }
        restored_event = note
        return NIP37Draft(unwrapped_note: note, draft_id: id, is_private_reply: is_private_reply)
    }

    /// Instantiates a draft object from a NIP-37 draft
    /// - Parameters:
    ///   - nip37_draft: The NIP-37 draft object
    ///   - damus_state: Damus state of the user who wants to load this draft object. Needed for pulling profiles from Ndb.
    /// - Returns: A draft artifacts object, or `nil` if such cannot be loaded.
    static func from(nip37_draft: NIP37Draft, damus_state: DamusState) -> DraftArtifacts? {
        let artifacts = Self.from(
            event: nip37_draft.unwrapped_note,
            draft_id: nip37_draft.id,
            damus_state: damus_state
        )
        artifacts?.is_private_reply = nip37_draft.is_private_reply
        return artifacts
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
        let artifacts = Self.from(parsed_blocks: parsed_blocks, references: Array(event.references),
                                  draft_id: draft_id, damus_state: damus_state, quoted_note_id: Self.quoteID(in: event))
        artifacts.restored_event = event
        return artifacts
    }
    
    /// Load a draft artifacts object from parsed Nostr event blocks
    /// 
    /// - Parameters:
    ///   - parsed_blocks: The blocks parsed from a Nostr event
    ///   - references: The references in the Nostr event
    ///   - draft_id: The unique ID of the draft as per NIP-37
    ///   - damus_state: Damus state, used for fetching profile info in NostrDB
    /// - Returns: The draft that can be loaded into `PostView`.
    static func from(parsed_blocks: Blocks, references: [RefId], draft_id: String, damus_state: DamusState, quoted_note_id: NoteId? = nil) -> DraftArtifacts {
        let rich_text_content: NSMutableAttributedString = .init(string: "")
        var media: [UploadedMedia] = []
        let quote_index = quoted_note_id.flatMap { id in
            parsed_blocks.blocks.lastIndex { block in
                guard case .mention(let mention) = block else { return false }
                return Self.quotedNoteID(mention.ref.nip19) == id
            }
        }
        for (index, block) in parsed_blocks.blocks.enumerated() {
            switch block {
            case .mention(let mention):
                if let pubkey = mention.ref.nip19.pubkey() {
                    // A profile reference, format things properly.
                    let profile = try? damus_state.profiles.lookup(id: pubkey)
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
                } else if index == quote_index {
                    // Remove only the selected quote; preserve other typed event references.
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
///
/// ## How drafts are stored
///
/// A draft is a NIP-37 kind-31234 event carrying the drafted note's JSON, sealed inside a ``PNS``
/// envelope (kind 1080) and handed to NostrDB. NostrDB's ingester opens the envelope on its own
/// threadpool and stores the draft event as an ordinary note, so loading drafts back is a query —
/// ``load(from:)`` does no decryption on any thread, and there is no key material anywhere on the
/// path. It used to NIP-44 decrypt a draft per saved draft, `secp256k1_ecdh` and all, on the main
/// thread during launch.
///
/// NostrDB is also the index. There is no list of draft ids in `UserSettingsStore` any more: the
/// drafts are whatever a `kinds: [31234], authors: [us]` query says they are.
class Drafts: ObservableObject {
    @Published var post: DraftArtifacts? = nil
    @Published var replies: [NoteId: DraftArtifacts] = [:]
    @Published var quotes: [NoteId: DraftArtifacts] = [:]
    /// The drafts we have for highlights
    ///
    /// ## Implementation notes
    /// - Although in practice we also load drafts based on the highlight source for better UX (making it easier to find a draft), we need the keys to be of type `HighlightContentDraft` because we need the selected text information to be able to construct the NIP-37 draft, as well as to load that into post view.
    @Published var highlights: [HighlightContentDraft: DraftArtifacts] = [:]

    /// How many stored draft events a load will look at.
    ///
    /// Every autosave appends a new version of every draft — NostrDB has no delete and, despite
    /// `is_replaceable_kind`, no replaceable-event handling — so the number of kind-31234 notes grows
    /// with editing time rather than with the number of drafts. The query returns them newest-first,
    /// so this bounds the fold below without hiding any recently edited draft; older versions beyond
    /// it are dead weight that `ndb_prune` reclaims along with everything else.
    static let max_stored_draft_versions = 1000

    /// The ids of the drafts NostrDB is currently holding a live version of.
    ///
    /// This is how a *deleted* draft is noticed: it is in here and no longer in the published
    /// properties, which means the next ``save(damus_state:)`` has to tombstone it. Nothing removes a
    /// note from NostrDB, so forgetting a draft in memory is not enough to forget it on disk.
    private var stored_draft_ids: Set<String> = []

    /// Loads drafts from NostrDB.
    ///
    /// Every saved version of every draft matches the query, so the drafts are the newest note under
    /// each NIP-37 `d` tag. The fold that works that out only reads a tag and a timestamp off each
    /// note without copying it, and only the winners are parsed.
    ///
    /// Runs synchronously on the caller's thread, which is the main thread during launch. That is
    /// affordable now that there is no decryption in it, and it means the post composer can never
    /// open on a half-loaded `Drafts` and start a fresh post over a saved draft.
    func load(from damus_state: DamusState) {
        let author = damus_state.keypair.pubkey
        let ndb = damus_state.ndb

        guard let filter = try? NdbFilter(from: NostrFilter(kinds: [.draft], authors: [author])) else { return }
        guard let note_keys = try? ndb.query(filters: [filter], maxResults: Self.max_stored_draft_versions) else { return }

        // Newest version of each draft. `query` already sorts newest-first, but `created_at` has
        // one-second resolution and two autosaves can land inside the same second, so break ties on
        // the note key — NostrDB hands those out in write order, so the higher one was saved later.
        var newest: [String: (created_at: UInt32, note_key: NoteKey)] = [:]
        for note_key in note_keys {
            let entry = try? ndb.lookup_note_by_key(note_key, borrow: { maybe_note -> (String, UInt32)? in
                switch maybe_note {
                case .none: return nil
                case .some(let note):
                    // A draft event only ever reaches the database as a rumor NostrDB peeled out of
                    // one of our own PNS envelopes. Anything else carrying kind 31234 under our
                    // pubkey — a draft saved in the old, self-encrypted format, or a draft synced
                    // from another client, which we do not support — is not ours to read.
                    guard note.is_rumor else { return nil }
                    guard let draft_id = note.referenced_params.first?.param.string() else { return nil }
                    return (draft_id, note.createdAt)
                }
            })
            guard let (draft_id, created_at) = entry ?? nil else { continue }
            if let existing = newest[draft_id],
               (existing.created_at, existing.note_key) >= (created_at, note_key) { continue }
            newest[draft_id] = (created_at, note_key)
        }

        var loaded_ids: Set<String> = []
        for (draft_id, entry) in newest {
            guard let draft_note = try? ndb.lookup_note_by_key_and_copy(entry.note_key) else { continue }
            // Implementation note: This currently fails silently, because:
            // 1. Errors are unlikely and not expected
            // 2. It is not mission critical to recover from this error
            // 3. The changes that add a error view sheet with useful info is not yet merged in as of writing.
            guard self.load(draft_note: draft_note, with: damus_state) else { continue }
            loaded_ids.insert(draft_id)
        }
        self.stored_draft_ids = loaded_ids
    }

    /// Loads a specific NIP-37 draft event into this class, and says whether it landed anywhere.
    ///
    /// A draft that does not land — an empty tombstone, a kind we have no composer for — is not an
    /// error; it just means there is no draft there any more.
    @discardableResult
    func load(draft_note: NdbNote, with damus_state: DamusState) -> Bool {
        guard let nip37_draft = NIP37Draft(draft_note: draft_note) else { return false }
        let drafted_note = nip37_draft.unwrapped_note
        guard let known_kind = drafted_note.known_kind else { return false }
        guard let draft_artifacts = DraftArtifacts.from(nip37_draft: nip37_draft, damus_state: damus_state) else { return false }

        // Find out where to place this draft
        switch known_kind {
        case .text:
            if let replied_to_note_id = drafted_note.direct_replies() {
                self.replies[replied_to_note_id] = draft_artifacts
            }
            else if let quoted_note_id = DraftArtifacts.quoteID(in: drafted_note) {
                self.quotes[quoted_note_id] = draft_artifacts
            }
            else {
                self.post = draft_artifacts
            }
        case .highlight:
            guard let highlight = HighlightContentDraft(from: drafted_note) else { return false }
            self.highlights[highlight] = draft_artifacts
        default:
            return false
        }
        return true
    }



    /// Saves the drafts tracked by this class persistently into NostrDB.
    func save(damus_state: DamusState) async {
        guard let keypair = damus_state.keypair.to_full() else { return }
        guard let pns_key = try? PNS.key(for: keypair.privkey) else { return }

        // What the user still has open, read before anything is serialized: a draft that fails to
        // build is still a draft the user has, and must not be mistaken below for a deleted one.
        var live_draft_ids: Set<String> = []
        live_draft_ids.formUnion([self.post?.id].compactMap({ $0 }))
        live_draft_ids.formUnion(self.replies.values.map({ $0.id }))
        live_draft_ids.formUnion(self.quotes.values.map({ $0.id }))
        live_draft_ids.formUnion(self.highlights.values.map({ $0.id }))

        var draft_notes: [NIP59.Rumor] = []

        func append(_ nip37_draft: NIP37Draft?) {
            guard let nip37_draft else { return }
            guard let draft_note = try? nip37_draft.draft_note(author: keypair.pubkey) else { return }
            draft_notes.append(draft_note)
        }

        if let post_artifacts = self.post {
            append(try? await post_artifacts.to_nip37_draft(action: .posting(.user(damus_state.pubkey)), damus_state: damus_state))
        }
        for (replied_to_note_id, reply_artifacts) in self.replies {
            append(try? await reply_artifacts.to_nip37_draft(target: replied_to_note_id, is_quote: false, damus_state: damus_state))
        }
        for (quoted_note_id, quote_note_artifacts) in self.quotes {
            append(try? await quote_note_artifacts.to_nip37_draft(target: quoted_note_id, is_quote: true, damus_state: damus_state))
        }
        for (highlight, highlight_note_artifacts) in self.highlights {
            append(try? await highlight_note_artifacts.to_nip37_draft(action: .highlighting(highlight), damus_state: damus_state))
        }

        // Drafts that were stored and are no longer here have been deleted — the composer posted or
        // discarded them. NostrDB cannot forget a note, so retract them by saving an empty version.
        for deleted_draft_id in self.stored_draft_ids.subtracting(live_draft_ids) {
            draft_notes.append(NIP37Draft.tombstone(draft_id: deleted_draft_id, author: keypair.pubkey))
        }
        self.stored_draft_ids = live_draft_ids

        for draft_note in draft_notes {
            // Implementation note: We do not support draft synchronization with relays yet. Note that
            // the envelope below is addressed to a key derived from ours and is meaningful only to
            // this device's NostrDB, so it is not something that could be published as-is.
            // TODO: Once it is time to implement draft syncing with relays, please consider the following:
            // - Privacy: Sending drafts to the network leaks metadata about app activity, and may break user expectations
            // - Down-sync conflict resolution: Consider how to solve conflicts for different draft versions holding the same ID (e.g. edited in Damus, then another client, then Damus again)
            guard let envelope = try? PNS.envelope(rumor: draft_note, key: pns_key) else { continue }
            await damus_state.nostrNetwork.sendToNostrDB(event: envelope)
        }
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
