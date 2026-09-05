//
//  PrivateReplyTreatment.swift
//  damus
//
//  Created by Claude on 2026-09-05.
//

import SwiftUI

/// The other person who can see a private reply — the one participant who is not us.
///
/// A private reply has exactly two readers: whoever wrote it, and the single pubkey it `p`-tags. So
/// the counterparty is the author when we are the recipient, and the `p` tag when we are the author.
///
/// Returns `nil` for anything that is not a private reply, and for a malformed one that lost its
/// audience tag — the treatment then says "only you" rather than naming somebody wrong, which is the
/// right way to fail on a question the reader is trusting us to answer.
@MainActor
func private_reply_counterparty(event: NostrEvent, our_pubkey: Pubkey) -> Pubkey? {
    guard event.is_private_reply else { return nil }
    if event.pubkey != our_pubkey { return event.pubkey }
    return event.referenced_pubkeys.first
}

/// The badge a private reply carries wherever it is drawn: a lock, and the answer to the only
/// question a reader has about one — *who else can see this*.
///
/// Naming the counterparty rather than saying "Private" is the point. "Private" leaves the reader to
/// guess at the audience, and the guess a thread invites is "everyone in it", which is wrong: a
/// private reply reaches exactly one other person.
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
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            if !compact {
                if let counterparty = private_reply_counterparty(event: event, our_pubkey: damus_state.pubkey) {
                    let name = event_author_name(profiles: damus_state.profiles, pubkey: counterparty)
                    Text("Only you and \(name) can see this", comment: "Label on a note stating that it was sent privately and is visible only to the reader and one other person.")
                } else {
                    Text("Only you can see this", comment: "Label on a note stating that it was sent privately and is visible only to the reader.")
                }
            }
        }
        .font(.caption)
        .foregroundColor(DamusColors.success)
        .accessibilityElement(children: .combine)
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
