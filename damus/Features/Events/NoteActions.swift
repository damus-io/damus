//
//  NoteActions.swift
//  damus
//
//  Created by Claude on 2026-09-05.
//

import Foundation

/// Which of a note's actions its UI may offer.
///
/// Damus publishes a *new, signed event* for most of what the note menu and the action bar do: a
/// boost embeds the note's JSON in a kind 6, a quote embeds an `nevent` in a kind 1, a like is a
/// kind 7 and a zap request a kind 9734, both naming the note. The relay-egress guards in
/// `PostBox.send` and ``make_nostr_push_event(ev:)`` refuse to publish a *rumor* — and none of those
/// events is one. They are perfectly legitimate events that happen to contain, or point at, a note
/// that was never meant to leave its gift wrap.
///
/// So containment cannot live at egress. It has to live here, where the affordance is built, which
/// is also the only place it can be made to *disappear*. A disabled boost button invites a tap and
/// teaches nothing; a missing one is self-explanatory next to the lock badge
/// (``PrivateReplyBadge``).
///
/// This is a value rather than a set of `if`s scattered across two view files so that the decision
/// is testable without a view: `NoteActions.available(on:keypair:)` is exactly what the menu and the action
/// bar are built from, so a test on it is a test on the built menu.
struct NoteActions: OptionSet {
    let rawValue: UInt32

    /// Reply. A reply to a private note is itself private, which is the composer's job rather than
    /// this one's — but signing is not, see ``available(on:keypair:)``.
    static let reply = NoteActions(rawValue: 1 << 0)
    /// Boost (kind 6) and quote (a kind 1 carrying an `nevent`), the two halves of ``RepostAction``.
    static let repost = NoteActions(rawValue: 1 << 1)
    /// React, from the shaka button, the swipe menu, or the chat view's long-press picker. A public
    /// kind 7 on a public note, and a kind-7 *rumor* in its own gift wrap on one that came out of a
    /// wrap — see ``send_reaction(to:emoji:keypair:damus_state:)``, which is where that is decided.
    static let like = NoteActions(rawValue: 1 << 2)
    /// Zap (a kind 9734 zap request naming the note). Forced to ``ZapType/priv`` when the note is a
    /// rumor — see ``ZapType/forced(on:requested:ndb:)``.
    static let zap = NoteActions(rawValue: 1 << 3)
    /// Every way of handing the note to somebody else as a string: the iOS share sheet, Copy Link,
    /// and Copy note ID — all of which are the same `nevent` in different wrapping.
    static let share = NoteActions(rawValue: 1 << 4)
    /// Broadcast: push this exact note to every connected relay.
    static let broadcast = NoteActions(rawValue: 1 << 5)
    /// Copy note JSON (developer mode).
    static let copyJSON = NoteActions(rawValue: 1 << 6)
    /// Report (NIP-56) — a public signed event naming the note and its author.
    static let report = NoteActions(rawValue: 1 << 7)
    /// Mute conversation, which publishes the note's ``NostrEvent/thread_id()`` in our mutelist.
    static let muteThread = NoteActions(rawValue: 1 << 8)

    static let all: NoteActions = [
        .reply, .repost, .like, .zap, .share, .broadcast, .copyJSON, .report, .muteThread
    ]

    /// The actions that may be offered on `event` by someone holding `keypair`.
    ///
    /// Three subtractions, for three different reasons.
    ///
    /// **A rumor cannot be republished, pointed at, or handed on.** ``NdbNote/is_rumor`` is set only
    /// by nostrdb's gift-wrap unwrapper, so it marks exactly the notes that reached us inside a wrap
    /// and exist nowhere else: private replies (``NdbNote/is_private_reply``) and NIP-17 DMs. A boost
    /// embeds the rumor's JSON in the content of a new kind 6 and Copy note JSON puts it on the system
    /// pasteboard, so both republish the plaintext outright; Broadcast pushes the note itself;
    /// sharing hands on an `nevent` that resolves for nobody, a link to a note no one else can fetch;
    /// and a NIP-56 report is a public signed event naming a note no moderator can ever look at,
    /// which announces the private exchange in return for nothing.
    ///
    /// **Reacting and zapping are not on that list, and were.** The objection to them was real — a
    /// kind 7 and a kind 9734 each publish a *public* event naming the note and, through its `p` tag,
    /// its author, which announces to a relay that a private note reached you and who sent it. But
    /// the answer to that is to make the reaction and the zap private too, not to withhold the
    /// affordance: ``send_reaction(to:emoji:keypair:damus_state:)`` sends a kind-7 *rumor* in its own
    /// gift wrap, and a zap at a rumor is forced to ``ZapType/priv``. So what this flag now means is
    /// "may react" and "may zap", not "may publish a kind 7" — and the private form of each is
    /// chosen at the send path rather than here, because a view that had to pick would be a second
    /// place to get it wrong.
    ///
    /// One leak survives that and is accepted deliberately: a zap receipt is published by the
    /// recipient's LNURL server, not by us, and it names the rumor's id — the only thing about this
    /// feature that puts one on a relay. An observer cannot tell that id from any other note they do
    /// not happen to have, so it says less than it looks like it does.
    ///
    /// **Muting a conversation publishes a note id**, in our public mutelist, so it is only safe when
    /// the id is one the world already has — and for a rumor it is not. ``NostrEvent/thread_id()``
    /// falls back to the note's own id when it has no root ref, so muting a rumor that is not a reply
    /// publishes *the rumor's id*, which nobody but the two of us has ever seen. Unlike a reaction,
    /// this one has no private form to take: a mutelist is a public record by construction.
    ///
    /// It is tempting to keep the action for a private reply on the grounds that one always carries
    /// NIP-10 tags naming a public parent. That is true only of the ones this app builds — the
    /// builder refuses to make any other kind — and this predicate does not match only those. A
    /// kind-1 rumor is *any* note another client chose to send inside a wrap, reply or not. So the
    /// rule is the rumor, not the reply, and the loss is small: muting a private reply's conversation
    /// only ever meant muting its public parent thread, which is reachable from the parent note
    /// sitting directly above it.
    ///
    /// **Replying needs a key to sign with.** A pubkey-only login can *read* a private reply —
    /// nostrdb unwrapped it, so it is plaintext — but cannot sign a seal, so it cannot answer one at
    /// all. The affordance has to be absent rather than present and failing: unlike the public case,
    /// where a signed-out user opening the composer is merely a dead end, here there is no fallback
    /// a reply could quietly become. A public reply to a private note is the one thing this feature
    /// must never produce. Reacting to one is the same rule for the same reason — a private reaction
    /// is sealed by us — so ``like`` goes with ``reply``; a public reaction dressed up as a private
    /// one would be the same mistake wearing a smaller hat.
    ///
    /// What is left off this list entirely is what stays available on anything: Copy text (the
    /// reader can already read it), Copy user public key, Add bookmark (bookmarks live in
    /// `UserDefaults`, not in a published list — see ``BookmarksManager``), and Mute/Block user,
    /// which is how you deal with an abusive private reply and says nothing about this note.
    static func available(on event: NostrEvent, keypair: Keypair) -> NoteActions {
        var actions = NoteActions.all

        // Legacy kind 4 is signed rather than a rumor, so the check below does not catch it. Muting a
        // DM's thread was already not offered, and stays that way.
        if event.known_kind == .dm {
            actions.remove(.muteThread)
        }

        if event.is_rumor {
            actions.subtract([.repost, .share, .broadcast, .copyJSON, .report, .muteThread])
        }

        if keypair.privkey == nil {
            actions.remove(.reply)

            // A private reaction is a rumor we have to seal, exactly as a private reply is, so a
            // pubkey-only login cannot make one. Only for a rumor: reacting to a public note is
            // already a dead end that the signing sheet explains, and taking the button away there
            // would be a change to the public app that has nothing to do with this.
            if event.is_rumor {
                actions.remove(.like)
            }
        }

        return actions
    }
}
