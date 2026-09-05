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
/// is testable without a view: `NoteActions.available(on:)` is exactly what the menu and the action
/// bar are built from, so a test on it is a test on the built menu.
struct NoteActions: OptionSet {
    let rawValue: UInt32

    /// Reply. Always available — a reply to a private note is itself private, which is the
    /// composer's job rather than this one's.
    static let reply = NoteActions(rawValue: 1 << 0)
    /// Boost (kind 6) and quote (a kind 1 carrying an `nevent`), the two halves of ``RepostAction``.
    static let repost = NoteActions(rawValue: 1 << 1)
    /// React (kind 7), from the shaka button, the swipe menu, or the chat view's long-press picker.
    static let like = NoteActions(rawValue: 1 << 2)
    /// Zap (a kind 9734 zap request naming the note).
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

    /// The actions that may be offered on `event`.
    ///
    /// Two subtractions, for two different reasons.
    ///
    /// **A rumor cannot be republished, pointed at, or handed on.** ``NdbNote/is_rumor`` is set only
    /// by nostrdb's gift-wrap unwrapper, so it marks exactly the notes that reached us inside a wrap
    /// and exist nowhere else: private replies (``NdbNote/is_private_reply``) and NIP-17 DMs. Every
    /// action removed here either republishes the plaintext (boost, quote, Broadcast, Copy note
    /// JSON) or publishes a public event pointing at it (like, zap, report). The latter are not
    /// content leaks, but they announce to a relay that you received a private note and — through
    /// the `p` tag — who sent it, which is the correlation the wrap exists to prevent. Sharing is
    /// removed because the `nevent` resolves for nobody: it is a link to a note no one else can
    /// fetch.
    ///
    /// **Muting a conversation publishes a note id**, in our public mutelist, so it is only safe when
    /// the id is one the world already has — and for a rumor it is not. ``NostrEvent/thread_id()``
    /// falls back to the note's own id when it has no root ref, so muting a rumor that is not a reply
    /// publishes *the rumor's id*, which nobody but the two of us has ever seen.
    ///
    /// It is tempting to keep the action for a private reply on the grounds that one always carries
    /// NIP-10 tags naming a public parent. That is true only of the ones this app builds — the
    /// builder refuses to make any other kind — and this predicate does not match only those. A
    /// kind-1 rumor is *any* note another client chose to send inside a wrap, reply or not. So the
    /// rule is the rumor, not the reply, and the loss is small: muting a private reply's conversation
    /// only ever meant muting its public parent thread, which is reachable from the parent note
    /// sitting directly above it.
    ///
    /// What is left off this list entirely is what stays available on anything: Copy text (the
    /// reader can already read it), Copy user public key, Add bookmark (bookmarks live in
    /// `UserDefaults`, not in a published list — see ``BookmarksManager``), and Mute/Block user,
    /// which is how you deal with an abusive private reply and says nothing about this note.
    static func available(on event: NostrEvent) -> NoteActions {
        var actions = NoteActions.all

        // Legacy kind 4 is signed rather than a rumor, so the check below does not catch it. Muting a
        // DM's thread was already not offered, and stays that way.
        if event.known_kind == .dm {
            actions.remove(.muteThread)
        }

        if event.is_rumor {
            actions.subtract([.repost, .like, .zap, .share, .broadcast, .copyJSON, .report, .muteThread])
        }

        return actions
    }
}
