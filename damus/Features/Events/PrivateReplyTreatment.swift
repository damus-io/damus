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
/// A private reply carries exactly one `p` tag, and on a private reply a `p` tag is not a mention,
/// it *is* the audience: ``NIP59/createPrivateReply(_:replyingTo:keypair:)`` strips the thread's `p`
/// tags and appends the single recipient. So the answer does not depend on who is asking. Both people
/// a private reply exists for read the same sentence off the same tag, which is the property that
/// lets the composer and the note say the same thing — see ``PrivateReplyAudienceLabel``.
///
/// Returns `nil` for anything that is not a private reply, and for a malformed one that lost its
/// audience tag — the label then says "Replying privately" rather than naming somebody wrong, which
/// is the right way to fail on a question the reader is trusting us to answer.
@MainActor
func private_reply_audience(of event: NostrEvent) -> Pubkey? {
    guard event.is_private_reply else { return nil }
    return event.referenced_pubkeys.first
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
