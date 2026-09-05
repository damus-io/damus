//
//  PrivateReply.swift
//  damus
//
//  Created by Claude on 2026-09-05.
//
import Foundation

/// A **private reply**: an ordinary kind-1 reply that never leaves its NIP-59 gift wrap.
///
/// Damus can say something publicly or say it in a DM, and there is nothing in between. A private
/// reply is the in-between: it carries ordinary NIP-10 reply tags, so it knows exactly which note it
/// answers and parses as a reply to that note, but the only thing published is a pair of kind-1059
/// wraps — one to the parent note's author, one to ourselves. On the wire it is indistinguishable
/// from a NIP-17 DM.
///
/// This is a thin layer over ``NIP59``, exactly as ``NIP17`` is: ``NIP59/giftWrap(rumor:sender:receiver:now:)``
/// is kind-agnostic and wraps a kind 1 as happily as it wraps a kind 14. All this file decides is
/// what goes in the rumor and who the wraps are addressed to.
///
/// Like ``NIP17``, this is the send side only. There is no receive side in Swift: nostrdb's ingester
/// peels inbound wraps and stores the kind-1 rumor inside as an ordinary plaintext note, which the
/// read side recognises with ``NdbNote/is_private_reply``. Reacting to one is the same construction
/// with a different kind in the rumor — see ``NIP59/createPrivateReaction(to:content:keypair:createdAt:)``.
extension NIP59 {
    /// Builds a private reply to `parent`: a kind-1 rumor, sealed and wrapped once for its audience
    /// and once for ourselves.
    ///
    /// The rumor's content and tags come straight from ``NostrPost/rendered(clientTag:)``, the same
    /// rendering ``NostrPost/to_event(keypair:clientTag:)`` uses, so a private reply's NIP-10 reply
    /// tags are byte-identical to those of the public reply it could have been. Only the `p` tags
    /// differ, and deliberately: they are replaced by a single one naming ``PrivateEvent/audience``,
    /// because on a private reply the `p` tags are not a mention list, they are *the audience*.
    ///
    /// **No marker tag.** The design called for one — something a client that peels a wrap
    /// generically would read as "do not re-broadcast this". It buys nothing: a rumor is unsigned, so
    /// there is no version of it any relay would accept, and a client determined to leak the contents
    /// would have to re-sign them as a note of its own, which no tag we write here prevents. The
    /// rumor carries exactly the tags the reply needs and nothing decorative.
    ///
    /// **One person, and nobody else.** Not every participant in the thread: that fan-out grows with
    /// the thread, needs a kind-10050 lookup per recipient, and produces a conversation where
    /// different readers see different subsets of the replies. Who that one person is, is
    /// ``privateAudience(for:as:)`` — so a private sub-thread stays 1:1 for its whole length and the
    /// audience never silently widens.
    ///
    /// - Parameters:
    ///   - post: the reply as `build_post` produced it — the same value the public path would have
    ///     handed to ``NostrPost/to_event(keypair:clientTag:)``.
    ///   - parent: the note being replied to. Its `id` is checked against the reply tags `post`
    ///     already carries, and ``NIP59/privateAudience(for:as:)`` reads the audience off it.
    ///     It may itself be a private reply, in which case its `pubkey` is the real sender nostrdb
    ///     copied off the seal.
    ///   - keypair: our own keys. A *full* keypair, non-optionally, because the seal has to be signed
    ///     by us: a pubkey-only login cannot make a private reply, and requiring the type here means
    ///     the composer has to establish that before it can offer the affordance, rather than
    ///     discovering it at send time.
    ///   - createdAt: the real send time, which is the rumor's `created_at` and what the thread orders
    ///     by. Unlike the seal's and the wraps', it is not fuzzed: it is inside the encryption, so
    ///     nobody but the two of us ever sees it.
    static func createPrivateReply(_ post: NostrPost,
                                   replyingTo parent: NostrEvent,
                                   keypair: FullKeypair,
                                   createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) throws -> PrivateEvent {
        let receiver = privateAudience(for: parent, as: keypair.pubkey)
        let rendered = post.rendered()

        // The reply tags come from `build_post`, which needs relay hints this builder has no way to
        // look up. So refuse a post that is not already a reply to `parent` rather than quietly
        // wrapping a note with no parent: a private reply that lost its `e` tag is not a slightly
        // worse reply, it is a message that appears in no thread at all and that neither party can
        // place. It is also the exact mistake a composer makes by passing the wrong `PostAction`.
        guard rendered.tags.contains(where: { $0.first == "e" && $0[safe: 1] == parent.id.hex() }) else {
            throw PrivateReplyError.notAReplyToTheParent
        }

        // Drop every `p` tag the public path would have carried — the parent's author, the other
        // thread participants, anyone @-mentioned in the text — and put back exactly one. A `p` tag on
        // a rumor reads as "deliver this to them", and a stray one would either widen the audience in
        // another client's eyes or promise a delivery we never make.
        var tags = rendered.tags.filter({ $0.first != "p" })
        tags.append(["p", receiver.hex()])

        let rumor = NIP59.Rumor(pubkey: keypair.pubkey,
                                kind: NostrKind.text.rawValue,
                                tags: tags,
                                content: rendered.content,
                                createdAt: createdAt)

        return try privateEvent(rumor: rumor, to: receiver, from: keypair)
    }

    enum PrivateReplyError: Error {
        /// The post handed to ``createPrivateReply(_:replyingTo:keypair:createdAt:)`` carries no
        /// NIP-10 `e` tag naming the parent, so it is not a reply to it and cannot be made into one
        /// here — the reply tags are `build_post`'s job.
        case notAReplyToTheParent
    }
}
