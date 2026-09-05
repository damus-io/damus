//
//  NIP37Draft.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-01-20.
//
import Foundation

/// This models a NIP-37 draft.
///
/// It is an immutable data structure that automatically makes both sides of a NIP-37 draft available:
/// the note that is being drafted, and the kind-31234 draft event that carries it.
///
/// This is useful for keeping it or passing it around to other functions when both sides will be
/// used, or it is not known which side of it will be used. Just initialize it, and read its
/// properties.
///
/// ## Where the encryption went
///
/// NIP-37 has the draft event encrypt its own content to the author (NIP-44, self-to-self). We do not
/// do that: the draft event is stored inside a ``PNS`` envelope, which encrypts it wholesale under a
/// symmetric key nostrdb already holds, so encrypting it a second time would buy nothing and cost a
/// `secp256k1_ecdh` per draft on every load. What is stored is therefore a kind-31234 whose content
/// is the drafted event's JSON in the clear, wrapped in a kind 1080.
///
/// The draft event is left **unsigned** — a rumor, in the NIP-59 sense, which is the form nostrdb
/// hands back on the way out. A draft is a note the user has not decided to publish; signing it would
/// manufacture a publishable event out of that indecision, and the signature would be checked by
/// nobody, since a draft never leaves the device.
struct NIP37Draft {
    // MARK: Properties
    // Implementation note: Must be immutable to maintain integrity of the structure.

    /// The unwrapped version of the draft. That is, the actual note that was being drafted.
    let unwrapped_note: NdbNote
    /// The unique ID of the draft, as per NIP-37 — the `d` tag of the kind-31234 draft event.
    let id: String
    /// Whether the draft is of a **private reply**, and so must come back with its lock still on.
    ///
    /// This lives on the draft event, not on ``unwrapped_note``. A private reply's rumor is
    /// byte-identical to the public reply it could have been (see
    /// ``NIP59/createPrivateReply(_:replyingTo:keypair:createdAt:)``), and the drafted note is that
    /// same rendering — so there is nothing in it that says "private", and there must not be: a
    /// marker inside it would change the note the composer round-trips into, and the two paths would
    /// stop producing the same bytes. The wrapper is local-only storage that never leaves the device,
    /// which makes it the right place for a flag about how the composer should reopen.
    let is_private_reply: Bool

    /// The marker tag on the kind-31234 wrapper that says the drafted reply is a private one.
    ///
    /// A bare presence tag: present means private, absent means public. Absent has to mean public
    /// because every draft saved before this feature existed is a public one, and reading those as
    /// private would put a lock on notes the user never locked.
    static let private_reply_tag = "private_reply"


    // MARK: Initialization

    /// Initializes object with an event to be drafted
    /// - Parameters:
    ///   - unwrapped_note: the note being drafted
    ///   - draft_id: the unique ID of this draft, as per NIP-37
    ///   - is_private_reply: whether the drafted reply is a private one
    init(unwrapped_note: NdbNote, draft_id: String, is_private_reply: Bool = false) {
        self.unwrapped_note = unwrapped_note
        self.id = draft_id
        self.is_private_reply = is_private_reply
    }

    /// Initializes object from a stored kind-31234 draft event, if it carries a note we can read.
    /// - Parameter draft_note: the kind-31234 note nostrdb unwrapped out of a ``PNS`` envelope
    init?(draft_note: NdbNote) {
        guard let draft_id = draft_note.referenced_params.first?.param.string() else { return nil }
        guard let unwrapped_note = Self.unwrap(draft_note: draft_note) else { return nil }
        self.unwrapped_note = unwrapped_note
        self.id = draft_id
        self.is_private_reply = draft_note.tags.contains(where: { $0.count == 1 && $0[0].string() == Self.private_reply_tag })
    }


    // MARK: Wrapping and unwrapping

    /// The kind-31234 NIP-37 draft event carrying ``unwrapped_note``: unsigned, with the drafted
    /// event's JSON as its plaintext content.
    ///
    /// This is what goes inside a ``PNS`` envelope, and what nostrdb stores and a load later queries
    /// for. `author` is the pubkey the draft belongs to, which is what that query filters on.
    func draft_note(author: Pubkey, createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) throws -> NIP59.Rumor {
        let note_json_data = try JSONEncoder().encode(self.unwrapped_note)
        guard let note_json_string = String(data: note_json_data, encoding: .utf8) else {
            throw NIP37DraftEventError.encoding_error
        }
        var tags = [
            ["d", self.id],
            ["k", String(self.unwrapped_note.kind)],
        ]

        if let replied_to_note = self.unwrapped_note.direct_replies() {
            tags.append(["e", replied_to_note.hex()])
        }

        if self.is_private_reply {
            tags.append([Self.private_reply_tag])
        }

        return NIP59.Rumor(pubkey: author,
                           kind: NostrKind.draft.rawValue,
                           tags: tags,
                           content: note_json_string,
                           createdAt: createdAt)
    }

    /// A function that reads the drafted note back out of a NIP-37 draft event
    /// - Parameter draft_note: kind-31234 note to be unwrapped
    /// - Returns: The note that was being drafted, if its content parses as one.
    static func unwrap(draft_note: NdbNote) -> NdbNote? {
        guard draft_note.known_kind == .draft else { return nil }
        return NdbNote.owned_from_json(json: draft_note.content)
    }

    /// A tombstone for a draft the user has deleted: a kind-31234 with the draft's `d` tag and no
    /// content.
    ///
    /// NostrDB has no delete, and — despite `is_replaceable_kind` — no replaceable-event handling
    /// either: every version of every draft ever saved stays queryable, and a load resolves a draft
    /// to the newest note carrying its `d` tag (see ``Drafts/load(from:)``). So the way to retract a
    /// draft is to make its newest version an empty one, which ``unwrap(draft_note:)`` then declines
    /// to read back.
    static func tombstone(draft_id: String, author: Pubkey, createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) -> NIP59.Rumor {
        return NIP59.Rumor(pubkey: author,
                           kind: NostrKind.draft.rawValue,
                           tags: [["d", draft_id]],
                           content: "",
                           createdAt: createdAt)
    }

    enum NIP37DraftEventError: Error {
        case invalid_keypair
        case encoding_error
    }
}
