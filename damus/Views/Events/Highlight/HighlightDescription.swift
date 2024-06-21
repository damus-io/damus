//
//  HighlightDescription.swift
//  damus
//
//  Created by eric on 4/28/24.
//

import SwiftUI

// Modified from Reply Description
struct HighlightDescription: View {
    let event: NostrEvent
    let highlighted_event: NostrEvent?
    let ndb: Ndb

    var body: some View {
        (Text(Image(systemName: "highlighter")) + Text(verbatim: " \(highlight_desc(ndb: ndb, event: event, highlighted_event: highlighted_event))"))
            .font(.footnote)
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)

    }
}

struct HighlightDescription_Previews: PreviewProvider {
    static var previews: some View {
        HighlightDescription(event: test_note, highlighted_event: test_note, ndb: test_damus_state.ndb)
    }
}

func highlight_desc(ndb: Ndb, event: NostrEvent, highlighted_event: NostrEvent?, locale: Locale = Locale.current) -> String {
    let desc = make_reply_description(event, replying_to: highlighted_event)
    let pubkeys = desc.pubkeys

    let bundle = bundleForLocale(locale: locale)

    if pubkeys.count == 0 {
        return NSLocalizedString("Highlighted", bundle: bundle, comment: "Label to indicate that the user is highlighting their own post.")
    }

    guard let profile_txn = NdbTxn(ndb: ndb) else  {
        return ""
    }

    let names: [String] = pubkeys.map { pk in
        let prof = ndb.lookup_profile_with_txn(pk, txn: profile_txn)

        return Profile.displayName(profile: prof?.profile, pubkey: pk).username.truncate(maxLength: 50)
    }

    let uniqueNames: [String] = Array(Set(names))
    return String(format: NSLocalizedString("Highlighted %@", bundle: bundle, comment: "Label to indicate that the user is highlighting 1 user."), locale: locale, uniqueNames.first ?? "")
}
