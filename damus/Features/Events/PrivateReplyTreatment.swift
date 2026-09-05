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
/// it has been sent (``PrivateReplyBadge``), from this one view, in the same words and the same green.
/// They are answering the same question — *who else can see this* — and a user who met two different
/// sentences for it would be right to wonder which of them was true.
///
/// Naming the recipient rather than saying "Private" is the point. "Private" leaves the reader to
/// guess at the audience, and the guess a thread invites is "everyone in it", which is wrong: a
/// private reply reaches exactly one other person.
///
/// The recipient is named even when it is the reader — as "you", because a note somebody sent *us* is
/// still a reply addressed to one person, and that person is us. Saying it from the note's point of
/// view rather than the reader's is what keeps it one sentence instead of two.
struct PrivateReplyAudienceLabel: View {
    let damus_state: DamusState
    /// Who the reply is addressed to, or `nil` when we cannot say. See ``private_reply_audience(of:)``.
    let recipient: Pubkey?
    /// Whether to draw the compact form — just the lock — for places with no room for a sentence.
    var compact: Bool = false
    /// The type size to draw at. The note badge is chrome and sits at `.caption`; the composer's line
    /// matches the public "Replying to @a, @b" line it replaces, which is `.footnote`.
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
            if !compact {
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
        }
        .font(font)
        .foregroundColor(DamusColors.success)
        .accessibilityElement(children: .combine)
    }
}

/// The badge a private reply carries wherever it is drawn: ``PrivateReplyAudienceLabel``, over the
/// note.
///
/// This badge is the *whole* treatment. It carries the information; a tint or a border around the
/// note would only repeat, less precisely, what the lock already says, and it would say it
/// differently on each surface — a bordered box reads as one thing in a timeline and as another
/// inside a chat bubble that already has a background of its own. One badge, drawn the same way
/// everywhere, is what makes a private reply recognisable at a glance across all of them.
struct PrivateReplyBadge: View {
    let damus_state: DamusState
    let event: NostrEvent
    /// Whether to draw the compact form — just the lock — for places with no room for a sentence.
    var compact: Bool = false

    var body: some View {
        PrivateReplyAudienceLabel(damus_state: damus_state,
                                  recipient: private_reply_audience(of: event),
                                  compact: compact)
    }
}

extension View {
    /// Renders this note as a private one when it is a private reply, and leaves it untouched when it
    /// is not.
    ///
    /// This is the marker the whole feature rests on. A private reply is a kind-1 rumor, plaintext in
    /// nostrdb and indistinguishable *by kind* from a public note, so it comes back from every
    /// `kinds: [1]` query the app makes and turns up on every surface that draws one: the home
    /// timeline, profile timelines, search results, quote previews, notifications. Rather than keeping
    /// it off those surfaces, the note itself says what it is — so the treatment has to live in the
    /// shared note chrome, not in any one screen, or a surface nobody thought about draws it bare.
    ///
    /// All this adds is ``PrivateReplyBadge``, above the note. The renderers that draw their own
    /// chrome — `ChatEventView`, `SelectedEventView`, `ReplyQuoteView` — place the same badge by
    /// hand, so every surface shows a private reply the same way whether it goes through here or
    /// not.
    ///
    /// - Parameter compact: draw just the lock, for chrome with no room for a sentence.
    @MainActor
    func privateReplyTreatment(damus_state: DamusState, event: NostrEvent, compact: Bool = false) -> some View {
        modifier(PrivateReplyTreatment(damus_state: damus_state, event: event, compact: compact))
    }
}

/// See ``SwiftUI/View/privateReplyTreatment(damus_state:event:compact:)``.
struct PrivateReplyTreatment: ViewModifier {
    let damus_state: DamusState
    let event: NostrEvent
    let compact: Bool

    func body(content: Content) -> some View {
        if event.is_private_reply {
            VStack(alignment: .leading, spacing: 4) {
                // Inset to the same gutter the note's own rows use, so the lock lines up with the
                // name and the text rather than hanging off the leading edge.
                PrivateReplyBadge(damus_state: damus_state, event: event, compact: compact)
                    .padding(.horizontal)
                content
            }
        } else {
            content
        }
    }
}

struct PrivateReplyTreatment_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: "An ordinary public note, untouched by the modifier.")
                .privateReplyTreatment(damus_state: test_damus_state, event: test_note)

            Text(verbatim: "What a private reply looks like once the rumor flag is set.")
        }
        .padding()
    }
}
