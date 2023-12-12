//
//  ReplyDescription.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

// jb55 - TODO: this could be a lot better
struct ReplyDescription: View {
    let event: NostrEvent
    let replying_to: NostrEvent?
    let ndb: Ndb

    var body: some View {
        Text(verbatim: "\(reply_desc(ndb: ndb, event: event, replying_to: replying_to))")
            .font(.footnote)
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReplyDescription_Previews: PreviewProvider {
    static var previews: some View {
        ReplyDescription(event: test_note, replying_to: test_note, ndb: test_damus_state.ndb)
    }
}

func reply_desc(ndb: Ndb, event: NostrEvent, replying_to: NostrEvent?, locale: Locale = Locale.current) -> String {
    let desc = make_reply_description(event, replying_to: replying_to)
    let pubkeys = desc.pubkeys
    let n = desc.others

    let bundle = bundleForLocale(locale: locale)

    if desc.pubkeys.count == 0 {
        return NSLocalizedString("Replying to self", bundle: bundle, comment: "Label to indicate that the user is replying to themself.")
    }

    guard let profile_txn = NdbTxn(ndb: ndb) else  {
        return ""
    }

    let names: [String] = pubkeys.map { pk in
        let prof = ndb.lookup_profile_with_txn(pk, txn: profile_txn)

        return Profile.displayName(profile: prof?.profile, pubkey: pk).username.truncate(maxLength: 50)
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


