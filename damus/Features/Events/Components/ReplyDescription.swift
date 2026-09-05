//
//  ReplyDescription.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

/// The line under a note's author naming who it is a reply to.
///
/// One line, one position, two kinds of note. A public reply lists the thread's `p` tags in gray —
/// "Replying to @a, @b" — and a private one names its single audience in green behind a lock —
/// "Replying privately to @a". They are the same statement about the same note, so they are drawn in
/// the same place and differ only in words and colour, exactly as they do in the composer
/// (``ReplyView/ReplyingToSection``). Anything that instead *added* the private sentence would be
/// saying it twice, since the public line names that same person too: a private reply's only `p` tag
/// is its recipient.
// jb55 - TODO: this could be a lot better
struct ReplyDescription: View {
    let state: DamusState
    let event: NostrEvent
    let replying_to: NostrEvent?

    var body: some View {
        Group {
            if event.is_private_reply {
                PrivateReplyBadge(damus_state: state, event: event, font: .footnote)
            } else {
                Text(verbatim: "\(reply_desc(ndb: state.ndb, event: event, replying_to: replying_to))")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReplyDescription_Previews: PreviewProvider {
    static var previews: some View {
        ReplyDescription(state: test_damus_state, event: test_note, replying_to: test_note)
    }
}

/// The public form of ``ReplyDescription``'s line. The private form is
/// ``PrivateReplyAudienceLabel``, which is a view rather than a string because the composer draws the
/// same sentence before there is any event to read it off, and one sentence written twice is how this
/// line came to disagree with itself in the first place.
func reply_desc(ndb: Ndb, event: NostrEvent, replying_to: NostrEvent?, locale: Locale = Locale.current) -> String {
    let desc = make_reply_description(event, replying_to: replying_to)
    let pubkeys = desc.pubkeys
    let n = desc.others

    let bundle = bundleForLocale(locale: locale)

    if desc.pubkeys.count == 0 {
        return NSLocalizedString("Replying to self", bundle: bundle, comment: "Label to indicate that the user is replying to themself.")
    }

    let names: [String] = pubkeys.map { pk in
        let profile = try? ndb.lookup_profile_and_copy(pk)

        return Profile.displayName(profile: profile, pubkey: pk).username.truncate(maxLength: 50)
    }
    
    let uniqueNames = NSOrderedSet(array: names).array as! [String]

    if uniqueNames.count > 1 {
        let othersCount = n - pubkeys.count
        if othersCount <= 0 {
            return String(format: NSLocalizedString("Replying to %@ & %@", bundle: bundle, comment: "Label to indicate that the user is replying to 2 users."), locale: locale, uniqueNames[0], uniqueNames[1])
        } else {
            return String(format: localizedStringFormat(key: "replying_to_two_and_others", locale: locale), locale: locale, othersCount, uniqueNames[0], uniqueNames[1])
        }
    }

    return String(format: NSLocalizedString("Replying to %@", bundle: bundle, comment: "Label to indicate that the user is replying to 1 user."), locale: locale, uniqueNames[0])
}
