//
//  PrivateReaction.swift
//  damus
//
//  Created by Claude on 2026-09-05.
//
import Foundation

/// A **private reaction**: an ordinary kind-7 reaction that never leaves its NIP-59 gift wrap.
///
/// Reacting to a private message used to be impossible, because a kind 7 is a *new, signed, public*
/// event naming the note it reacts to and that note's author — so on a message that only two people
/// have, it announces to a relay both that the message exists and who is talking to whom. The answer
/// is not to withhold the affordance but to make the reaction as private as the thing it reacts to:
/// the same rumor / seal / wrap construction, one kind lower down.
///
/// The receive side needs no new code at all. nostrdb's ingester peels *any* rumor kind, so an
/// inbound private reaction lands in the database as a plaintext kind 7 like any other, and the
/// existing notification filter (`kinds: [1, 6, 7, 9735], #p: <us>`) picks it up out of the local
/// database and counts it through ``HomeModel/handle_like_event(_:)``. That is why the rumor's single
/// `p` tag matters twice over: it is the audience, and it is also what makes the reaction show up on
/// the note.
extension NIP59 {
    /// Builds a private reaction to `reacted`: a kind-7 rumor, sealed and wrapped once for its
    /// audience and once for ourselves.
    ///
    /// **Two tags, and nothing else.** ``make_like_event(keypair:liked:content:relayURL:)`` copies
    /// every `e` and `p` tag off the note it reacts to, as NIP-25 asks, so that relays can serve the
    /// reaction to everyone following that thread. None of that applies here: a rumor is served to
    /// nobody, it is *delivered*, and delivery is what the wrap does. So the rumor carries one `e`
    /// tag naming what was reacted to and one `p` tag naming ``PrivateEvent/audience`` — because on a
    /// rumor the `p` tags are not a mention list, they are the audience, and a stray one would either
    /// widen that audience in another client's eyes or promise a delivery we never make. Copying the
    /// parent's thread tags would add public ids inside the encryption for no reader's benefit.
    ///
    /// - Parameters:
    ///   - reacted: the note being reacted to, which **must** be a rumor. Reacting to a public note is
    ///     the public path's job, and a private reaction to a public note would be worse than
    ///     pointless: the reaction would be invisible to everyone but its recipient while the user
    ///     believed they had reacted in public. The guard is ``NdbNote/is_rumor`` rather than a kind
    ///     check, because coming out of a gift wrap is the property that makes a public kind 7 unsafe
    ///     — as true of a NIP-17 DM as of a private reply.
    ///   - content: the reaction, an emoji or one of NIP-25's `+` / `-`. The same string the public
    ///     path would have put in a kind 7.
    ///   - keypair: our own keys, in full, because the seal has to be signed by us. A pubkey-only
    ///     login can read a private reply but cannot react to one at all — the same rule as replying.
    ///   - createdAt: the real reaction time, which is the rumor's `created_at`. Unlike the seal's and
    ///     the wraps', it is not fuzzed: it is inside the encryption, so nobody but the two of us
    ///     ever sees it.
    static func createPrivateReaction(to reacted: NostrEvent,
                                      content: String = "🤙",
                                      keypair: FullKeypair,
                                      createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) throws -> PrivateEvent {
        guard reacted.is_rumor else { throw PrivateReactionError.notPrivate }

        let receiver = privateAudience(for: reacted, as: keypair.pubkey)

        let rumor = NIP59.Rumor(pubkey: keypair.pubkey,
                                kind: NostrKind.like.rawValue,
                                tags: [["e", reacted.id.hex()], ["p", receiver.hex()]],
                                content: content,
                                createdAt: createdAt)

        return try privateEvent(rumor: rumor, to: receiver, from: keypair)
    }

    enum PrivateReactionError: Error {
        /// ``createPrivateReaction(to:content:keypair:createdAt:)`` was handed a note that did not come
        /// out of a gift wrap. Reacting to a public note publicly is not this builder's business, and
        /// doing it privately would hide a reaction the user meant everyone to see.
        case notPrivate
    }
}
