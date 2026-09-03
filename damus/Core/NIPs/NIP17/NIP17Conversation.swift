//
//  NIP17Conversation.swift
//  damus
//
//  Created by Claude on 2026-09-03.
//
import Foundation

/// ## Implementation notes
///
/// 1. Deliberately separate from `NIP17.swift`. This is the read side, and it is needed by the
///    notification extension, which formats an unwrapped kind-14 rumor into a push notification.
///    `NIP17.swift` is the send side and reaches `NIP59` and from there `NIP44`, none of which the
///    extension builds or has any use for. Folding this back in would drag that whole graph into the
///    extension target for one pure function over a note's `p` tags.

/// Which 1:1 conversation a NIP-17 kind-14 rumor belongs to, or `nil` if it belongs to none.
///
/// The rumor's author is the sender — nostrdb copies that off the seal — and its `p` tags are the
/// receivers, so the conversation is keyed on whichever end of the exchange is not us. A rumor whose
/// only participant is us is a note to self, keyed on our own pubkey.
///
/// Returns `nil` for a **group chat**, i.e. a rumor with more than one counterparty. We drop those
/// rather than folding them into a 1:1 thread with the first `p` tag, because such a thread lies in
/// both directions: it shows messages from participants the user cannot see, and a reply typed into
/// it reaches only that one counterparty while the user believes the whole group is reading it.
/// Damus has no group chat UI and no way to send to one, so there is nothing honest to render.
///
/// Also returns `nil` for a rumor we are not a party to at all, which the subscription filters
/// should already have excluded.
func nip17_conversation_pubkey(rumor ev: NostrEvent, our_pubkey: Pubkey) -> Pubkey? {
    // Some clients tag every participant, including the sender, so take the union of author and
    // `p` tags rather than trusting either alone to be the complete set.
    var participants = Set(ev.referenced_pubkeys)
    participants.insert(ev.pubkey)

    guard participants.contains(our_pubkey) else { return nil }

    let counterparties = participants.subtracting([our_pubkey])
    switch counterparties.count {
    case 0: return our_pubkey       // a note to self
    case 1: return counterparties.first
    default: return nil             // a group chat
    }
}
