//
//  PrivateReplySender.swift
//  damus
//
//  Created by Claude on 2026-09-05.
//
import Foundation

/// Sends a private reply: builds it, ingests our own copy, and publishes the two gift wraps.
///
/// This is the whole send side of the feature, and it is deliberately not the public posting path.
/// A private reply never becomes a ``NostrEvent``, so there is nothing here for `PostBox` to send and
/// nothing for the relay-egress guards to catch — the only things that reach a relay are the two
/// kind-1059 wraps, published the same way a NIP-17 DM's are.
///
/// Modelled on `DMChatView.send_message`, which is the working reference for this shape.
///
/// - Parameters:
///   - post: the reply as `build_post` produced it, identical to what the public path would have
///     signed.
///   - parent: the note being replied to. Who the reply is addressed to is read off it by
///     ``NIP59/privateReplyAudience(replyingTo:as:)``.
///   - keypair: our own keys, in full — the seal has to be signed by us.
/// - Returns: whether the reply was built and handed to the publish path. `false` means nothing was
///   sent and the composer should stay open with the user's text in it.
@MainActor
func send_private_reply(_ post: NostrPost,
                        replyingTo parent: NostrEvent,
                        keypair: FullKeypair,
                        damus_state: DamusState) async -> Bool {
    let reply: NIP59.PrivateReply
    do {
        reply = try NIP59.createPrivateReply(post, replyingTo: parent, keypair: keypair)
    }
    catch {
        Log.error("Failed to build a private reply: %s", for: .networking, error.localizedDescription)
        return false
    }

    // Ingest **only** our own wrap, and let the reply appear through the real read path rather than
    // by optimistic insert: nostrdb peels it and the thread's existing kind-1 query delivers the
    // rumor. A wrap we built wrong then fails visibly here, at send time, instead of quietly becoming
    // history neither party can open.
    //
    // The receiver's wrap must never be ingested. We cannot decrypt it, so it would sit in the
    // database forever as an un-openable kind 1059 that every giftwrap backfill retries at launch.
    do { try damus_state.ndb.add(event: reply.giftWrapToSelf) }
    catch {
        // The reply is on its way regardless; it will show up once a relay echoes our own wrap back
        // to the giftwrap subscription. Losing the local copy only costs us the immediate echo.
        Log.error("Failed to ingest our own private reply giftwrap locally: %s", for: .ndb, error.localizedDescription)
    }

    // Each wrap goes to its own addressee's DM inbox relays, which is what makes it reachable rather
    // than merely valid. Ours goes first, and only then theirs: this half is a local read, while
    // looking up their kind-10050 may have to go ask the network for it, and the reply should not sit
    // unsent on our side for the length of someone else's relay round trip.
    let userRelayList = damus_state.nostrNetwork.userRelayList
    let ourInboxRelays = userRelayList.ourBestEffortDMInboxRelays()
    await damus_state.nostrNetwork.publishGiftWrap(reply.giftWrapToSelf, to: ourInboxRelays)

    if let wrapToReceiver = reply.giftWrapToReceiver {
        // `nil` only when replying to ourselves, where the two copies are the same copy. The audience
        // rather than `parent.pubkey`, because replying to a private reply of our own continues the
        // conversation with the person it was addressed to, not with ourselves. Their inbox list is
        // `nil` when they have published no kind-10050, which is still the common case; the publish
        // path falls back to our own write relays for it.
        let theirInboxRelays = await userRelayList.fetchDMInboxRelays(for: reply.audience)
        await damus_state.nostrNetwork.publishGiftWrap(wrapToReceiver, to: theirInboxRelays)
    }

    return true
}
