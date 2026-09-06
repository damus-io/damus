//
//  PrivateReplyTreatment.swift
//  damus
//
//  Created by Claude on 2026-09-05.
//

import SwiftUI

/// The person a private reply was addressed to — its audience, and the "@a" in "Replying privately
/// to @a".
///
/// **The audience is not a tag.** It is ``NdbNote/rumor_receiver_pubkey``: the pubkey of the key that
/// actually opened the gift wrap, which nostrdb copies into the rumor's repurposed signature field at
/// ingest (`memcpy(sig, unwrap_key->pubkey, 32)`). A sender cannot influence it — it is not read from
/// the wrap's `p` tag but from which of *our* keys decrypted the thing — and it is exactly the fact
/// the sentence is asserting: who this note was delivered to.
///
/// A `p` tag cannot answer it, and believing otherwise is what put the wrong name on the note. The
/// argument was that ``NIP59/createPrivateReply(_:replyingTo:keypair:)`` strips a thread's `p` tags
/// and appends exactly one naming the recipient, so on a private reply a `p` tag is not a mention, it
/// *is* the audience. True — of the notes *this app builds*. ``NdbNote/is_private_reply`` does not
/// match only those: it is `is_rumor && kind == 1`, so it is set for **any** kind 1 that came out of a
/// wrap addressed to us, however the sender chose to tag it. Another client wrapping an ordinary
/// NIP-10 reply keeps the thread's `p` tags, and in a thread rooted at the sender's own note the first
/// of those is the sender — so the first tag named the author of a note we had *received*, which is
/// the one thing the sentence can never be.
///
/// So the rumor is answered by where it was delivered, with one exception:
///
/// - **A rumor somebody else wrote.** It is here only because a wrap was addressed to us, so we are
///   the audience. ``NdbNote/rumor_receiver_pubkey`` says so, and no tag gets a vote.
/// - **A rumor we wrote.** The copy we can read is the wrap ``NIP59/privateEvent(rumor:to:from:)``
///   addresses to *ourselves* — the only copy of our own message we can decrypt — so its receiver is
///   us and says nothing about who else got one. Here the single `p` tag is the answer, and here it is
///   trustworthy: nostrdb copies a rumor's `pubkey` off the **seal**, a seal is signed, so a rumor
///   naming us as its author can only have been sealed by our own key. Nobody else can reach this
///   branch.
///
/// Which branch a note is on is a property of the note alone: ``NdbNote/rumor_receiver_pubkey`` is
/// always one of the keys registered with ``Ndb/add_key(_:)``, i.e. one of ours, so `pubkey ==
/// receiver` *is* "we wrote it" and the answer never depends on who is asking. That is what lets the
/// composer, the sender's copy and the recipient's copy carry one sentence — see
/// ``PrivateReplyAudienceLabel`` — even though the two ends now derive it from different fields.
///
/// Returns `nil` for anything that is not a private reply, and for the one case a note genuinely
/// cannot answer: a reply of *ours* carrying a thread's `p` tags rather than damus's single recipient
/// tag, where our own copy's receiver is us and the tags are a mention list. The label then says
/// "Replying privately" rather than naming somebody wrong, which is the right way to fail a question
/// the reader is trusting us to answer.
@MainActor
func private_reply_audience(of event: NostrEvent) -> Pubkey? {
    guard event.is_private_reply, let receiver = event.rumor_receiver_pubkey else { return nil }

    // A wrap addressed to somebody other than the note's author is one only *our* key could have
    // opened, so the person it was delivered to is us. Whatever the sender tagged is a mention list.
    guard event.pubkey == receiver else { return receiver }

    // Our own copy, wrapped to ourselves. Exactly one `p` tag is the shape this app's builder
    // produces and the only shape that can be read as an audience; several of them is a thread's
    // mention list, which names nobody in particular.
    let tagged = Array(event.referenced_pubkeys)
    guard tagged.count == 1 else { return nil }
    return tagged.first
}

/// The one sentence the app has for a private reply's audience: **"Replying privately to @a"**.
///
/// Drawn by the composer while the reply is being written (``ReplyView``) and by the note itself once
/// it has been sent (``ReplyDescription``), from this one view, in the same words and the same green.
/// They are answering the same question — *who else can see this* — and a user who met two different
/// sentences for it would be right to wonder which of them was true.
///
/// **It is never an extra line.** In both places it stands exactly where the public "Replying to @a,
/// @b" line stands and displaces it: the composer's line above the text field, and the note's own
/// reply description under the author's name. So a private reply states its audience in the slot a
/// public reply states its audience, and only the words and the colour change. Drawing it *as well*
/// as the public line — which is what a badge above the note amounts to — says the same fact twice
/// and says it somewhere a public reply's audience never appears, which reads as though the position
/// itself meant something.
///
/// Naming the recipient rather than saying "Private" is the point. "Private" leaves the reader to
/// guess at the audience, and the guess a thread invites is "everyone in it", which is wrong: a
/// private reply reaches exactly one other person.
///
/// The recipient is named even when it is the reader — as "you", because a note somebody sent *us* is
/// still a reply addressed to one person, and that person is us. Saying it from the note's point of
/// view rather than the reader's is what keeps it one sentence instead of two. Under the author's
/// name, which is where the note draws it, the sentence has its subject directly above it:
/// "npub1a4an…s4l3 · now / Replying privately to you".
struct PrivateReplyAudienceLabel: View {
    let damus_state: DamusState
    /// Who the reply is addressed to, or `nil` when we cannot say. See ``private_reply_audience(of:)``.
    let recipient: Pubkey?
    /// The type size to draw at. It matches whatever public line it is standing in for: `.footnote`
    /// for a reply description, `.caption` for the chat bubble's chrome.
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
            if let recipient {
                if recipient == damus_state.pubkey {
                    Text("Replying privately to you", comment: "Label on a private reply stating that it was sent only to the reader.")
                } else {
                    let name = event_author_name(profiles: damus_state.profiles, pubkey: recipient)
                    Text("Replying privately to \(Text(verbatim: "@" + name))", comment: "Label stating that a reply is encrypted and goes only to the named person, where the parameter is that person's username.")
                }
            } else {
                Text("Replying privately", comment: "Label stating that a reply is encrypted rather than posted publicly, when the person it goes to cannot be named.")
            }
        }
        .font(font)
        .foregroundColor(DamusColors.success)
        .accessibilityElement(children: .combine)
    }
}

/// ``PrivateReplyAudienceLabel`` for a note that already exists, with the audience read off the note
/// itself.
///
/// This is the *whole* treatment a private reply gets. It carries the information; a tint or a border
/// around the note would only repeat, less precisely, what the lock already says, and it would say it
/// differently on each surface — a bordered box reads as one thing in a timeline and as another
/// inside a chat bubble that already has a background of its own.
///
/// Almost every surface reaches this through ``ReplyDescription``, because a private reply is a reply
/// and every renderer of a note already draws a line saying what it is replying to. The exception is
/// ``ChatEventView``: a chat bubble draws the parent as a quote rather than as a sentence, so it has
/// no reply line to displace and places this badge itself. ``ReplyQuoteView`` — a one-line preview
/// with no room for a sentence — draws the bare lock by hand.
struct PrivateReplyBadge: View {
    let damus_state: DamusState
    let event: NostrEvent
    /// See ``PrivateReplyAudienceLabel/font``.
    var font: Font = .caption

    var body: some View {
        PrivateReplyAudienceLabel(damus_state: damus_state,
                                  recipient: private_reply_audience(of: event),
                                  font: font)
    }
}

struct PrivateReplyAudienceLabel_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 20) {
            PrivateReplyAudienceLabel(damus_state: test_damus_state, recipient: test_damus_state.pubkey, font: .footnote)
            PrivateReplyAudienceLabel(damus_state: test_damus_state, recipient: test_note.pubkey, font: .footnote)
            PrivateReplyAudienceLabel(damus_state: test_damus_state, recipient: nil, font: .footnote)
        }
        .padding()
    }
}
