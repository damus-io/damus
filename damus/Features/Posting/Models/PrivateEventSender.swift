//
//  PrivateEventSender.swift
//  damus
//
//  Created by Claude on 2026-09-05.
//
import Foundation
import UIKit

/// Publishes `priv`: ingests our own wrap locally and sends both wraps to the right inbox relays.
///
/// The shared half of every private send path, so that the two rules that make one correct cannot
/// drift apart between kinds. It is deliberately not the public posting path: nothing here ever
/// becomes a ``NostrEvent`` that `PostBox` could send, so there is nothing for the relay-egress
/// guards to catch — the only things that reach a relay are the kind-1059 wraps, published the same
/// way a NIP-17 DM's are.
///
/// Modelled on `DMChatView.send_message`, which is the working reference for this shape.
@MainActor
func publish_private_event(_ priv: NIP59.PrivateEvent, damus_state: DamusState) async {
    // Ingest **only** our own wrap, and let the message appear through the real read path rather than
    // by optimistic insert: nostrdb peels it and the app's existing plaintext queries deliver the
    // rumor. A wrap we built wrong then fails visibly here, at send time, instead of quietly becoming
    // history neither party can open.
    //
    // The receiver's wrap must never be ingested. We cannot decrypt it, so it would sit in the
    // database forever as an un-openable kind 1059 that every giftwrap backfill retries at launch.
    do { try damus_state.ndb.add(event: priv.giftWrapToSelf) }
    catch {
        // The message is on its way regardless; it will show up once a relay echoes our own wrap back
        // to the giftwrap subscription. Losing the local copy only costs us the immediate echo.
        Log.error("Failed to ingest our own giftwrap locally: %s", for: .ndb, error.localizedDescription)
    }

    // Each wrap goes to its own addressee's DM inbox relays, which is what makes it reachable rather
    // than merely valid. Ours goes first, and only then theirs: this half is a local read, while
    // looking up their kind-10050 may have to go ask the network for it, and the message should not
    // sit unsent on our side for the length of someone else's relay round trip.
    let userRelayList = damus_state.nostrNetwork.userRelayList
    let ourInboxRelays = userRelayList.ourBestEffortDMInboxRelays()
    await damus_state.nostrNetwork.publishGiftWrap(priv.giftWrapToSelf, to: ourInboxRelays)

    if let wrapToReceiver = priv.giftWrapToReceiver {
        // `nil` only when the audience is us, where the two copies are the same copy. Their inbox list
        // is `nil` when they have published no kind-10050, which is still the common case; the publish
        // path falls back to our own write relays for it.
        let theirInboxRelays = await userRelayList.fetchDMInboxRelays(for: priv.audience)
        await damus_state.nostrNetwork.publishGiftWrap(wrapToReceiver, to: theirInboxRelays)
    }
}

/// Sends a private reply: builds it, ingests our own copy, and publishes the two gift wraps.
///
/// - Parameters:
///   - post: the reply as `build_post` produced it, identical to what the public path would have
///     signed.
///   - parent: the note being replied to. Who the reply is addressed to is read off it by
///     ``NIP59/privateAudience(for:as:)``.
///   - keypair: our own keys, in full — the seal has to be signed by us.
/// - Returns: whether the reply was built and handed to the publish path. `false` means nothing was
///   sent and the composer should stay open with the user's text in it.
@MainActor
func send_private_reply(_ post: NostrPost,
                        replyingTo parent: NostrEvent,
                        keypair: FullKeypair,
                        damus_state: DamusState) async -> Bool {
    let reply: NIP59.PrivateEvent
    do {
        reply = try NIP59.createPrivateReply(post, replyingTo: parent, keypair: keypair)
    }
    catch {
        Log.error("Failed to build a private reply: %s", for: .networking, error.localizedDescription)
        return false
    }

    await publish_private_event(reply, damus_state: damus_state)
    return true
}

/// Reacts to `event` with `emoji`, publicly or privately according to what `event` is.
///
/// **The one branch, in one place.** Both callers of the old public path — the action bar's shaka
/// button and swipe action, and the chat bubble's long-press emoji picker — go through here, so
/// there is a single answer to "is this reaction safe to publish" rather than two `if`s that can
/// drift. The condition is ``NdbNote/is_rumor``, not a kind: a kind 7 naming a note that only two
/// people have is unsafe because that note came out of a gift wrap, which is as true of a NIP-17 DM
/// as of a private reply.
///
/// - Returns: the reaction as something the action bar can show as ours, or `nil` if nothing was
///   sent. For a public reaction that is the signed kind 7; for a private one it is the kind-7 rumor
///   read back out of nostrdb, which is a real ``NostrEvent`` carrying the rumor flag and so is
///   refused by both relay-egress guards if anything ever tries to publish it.
@MainActor
func send_reaction(to event: NostrEvent,
                   emoji: String,
                   keypair: FullKeypair,
                   damus_state: DamusState) async -> NostrEvent? {
    guard !event.is_rumor else {
        return await send_private_reaction(to: event, content: emoji, keypair: keypair, damus_state: damus_state)
    }

    guard let like_ev = make_like_event(keypair: keypair, liked: event, content: emoji,
                                        relayURL: await damus_state.nostrNetwork.relaysForEvent(event: event).first)
    else { return nil }

    await damus_state.nostrNetwork.postbox.send(like_ev)
    return like_ev
}

/// Sends a private reaction: a kind-7 rumor, wrapped and published exactly as a private reply is.
///
/// - Returns: our own reaction, read back out of nostrdb after the self-wrap is ingested, so that the
///   action bar shows what the database holds rather than an optimistic guess — and `nil` if the
///   ingest did not produce it, in which case the reaction is still on its way to the relay and will
///   appear when our own wrap is echoed back. The rumor is not returned directly because a
///   ``NIP59/Rumor`` is deliberately not a ``NostrEvent``: only the copy nostrdb peeled carries the
///   flag that keeps it off the wire.
@MainActor
func send_private_reaction(to event: NostrEvent,
                           content: String,
                           keypair: FullKeypair,
                           damus_state: DamusState) async -> NostrEvent? {
    let reaction: NIP59.PrivateEvent
    do {
        reaction = try NIP59.createPrivateReaction(to: event, content: content, keypair: keypair)
    }
    catch {
        Log.error("Failed to build a private reaction: %s", for: .networking, error.localizedDescription)
        return nil
    }

    await publish_private_event(reaction, damus_state: damus_state)

    // nostrdb ingests on its own threads, so our own copy is not readable the instant `add` returns.
    // Wait for it rather than handing the view an optimistic guess: what the action bar shows should
    // be what the database holds, and nostrdb's copy is the only form of this reaction that carries
    // the rumor flag — which is what keeps a view from ever handing it back to `PostBox`.
    for _ in 0..<100 {
        if let ours = try? damus_state.ndb.lookup_note_and_copy(reaction.rumor.id) { return ours }
        try? await Task.sleep(for: .milliseconds(20))
    }

    // The reaction is already on its way regardless; only the immediate echo is lost, and our own wrap
    // coming back from a relay will produce it later.
    Log.error("Private reaction %s never came back out of the ingester", for: .ndb, reaction.rumor.id.hex())
    return nil
}
